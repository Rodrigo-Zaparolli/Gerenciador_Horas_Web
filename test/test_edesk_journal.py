import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

os.environ['EDESK_LOCAL_MODE'] = 'true'
from cloud_run.main import app, automation_lock, operation_status
from local_edesk import journal

HEADERS = {'Origin': 'https://gerenciador-horas.web.app', 'Authorization': 'Bearer test'}


class JournalTests(unittest.TestCase):
    def test_new_uncertain_retry_is_not_erased_by_an_earlier_not_submitted_event(self):
        _, keys, _ = journal.prepare('owner', self.data)
        events = Path(self.directory.name) / 'events.jsonl'
        events.write_text('\n'.join(json.dumps({'key': keys[0], 'state': state})
            for state in ['started', 'not_submitted', 'started']))
        self.assertEqual(journal.finish('owner', keys, events), 1)
        self.assertEqual(journal.states('owner')[keys[0]], 'uncertain')

    def test_verified_hours_are_successful_even_if_browser_cleanup_fails(self):
        def run(*args, **kwargs):
            data = json.loads(Path(args[0][-1]).read_text(encoding='utf-8'))
            Path(kwargs['env']['EDESK_EVENTS_FILE']).write_text('\n'.join(
                json.dumps({'key': h['_sendKey'], 'state': 'confirmed'})
                for work in data['trabalhos'] for h in work['horas']))
            return process.return_value
        with patch('cloud_run.main.subprocess.Popen') as process:
            process.side_effect = run
            process.return_value.communicate.return_value = ('browser closed after verification', '')
            process.return_value.returncode = 1
            response = self.client.post('/api/edesk/horas', headers=HEADERS,
                json={'request': self.data, 'enviar': True})
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json['confirmed'])
        self.assertEqual(response.json['completed'], 3)
        self.assertIn('Nenhuma hora pendente', response.json['message'])

    def test_already_confirmed_selection_is_successful_without_launching_browser(self):
        _, keys, _ = journal.prepare('owner', self.data)
        journal.set_state('owner', keys, 'confirmed')
        with patch('cloud_run.main.subprocess.Popen') as process:
            response = self.client.post('/api/edesk/horas', headers=HEADERS,
                json={'request': self.data, 'enviar': True})
            process.assert_not_called()
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json['confirmed'])
    def test_retry_clears_old_failed_states_and_preserves_confirmed_hours(self):
        _, keys, _ = journal.prepare('owner', self.data)
        journal.set_state('owner', keys[:1], 'confirmed')
        journal.set_state('owner', keys[1:2], 'uncertain')
        journal.set_state('owner', keys[2:], 'pending')
        prepared, selected, skipped = journal.prepare('owner', self.data, True)
        self.assertEqual(journal.states('owner'), {keys[0]: 'confirmed'})
        self.assertEqual(selected, keys[1:])
        self.assertEqual(skipped, 1)
        self.assertTrue(all(h['_retryUnconfirmed'] for h in prepared['trabalhos'][0]['horas']))

    def test_failed_before_submission_is_released(self):
        _, keys, _ = journal.prepare('owner', self.data)
        journal.set_state('owner', keys, 'pending')
        events = Path(self.directory.name) / 'events.jsonl'
        events.write_text('\n'.join(json.dumps(e) for e in [
            {'key': keys[0], 'state': 'started'},
            {'key': keys[0], 'state': 'not_submitted'}]))
        self.assertEqual(journal.finish('owner', keys, events), 0)
        self.assertEqual(journal.states('owner'), {})
        self.assertEqual(journal.prepare('owner', self.data)[1], keys)

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.env = patch.dict(os.environ, {'EDESK_JOURNAL_PATH': str(Path(self.directory.name) / 'ledger.sqlite3')})
        self.env.start()
        self.auth = patch('local_edesk.authentication.verify_token', return_value={'sub': 'owner'})
        self.auth.start()
        self.client = app.test_client()
        self.work = {'solicitacao': '123', 'idTrabalho': '2', 'horas': [
            {'data': '08/10/2026', 'inicio': '08:00', 'fim': '09:00', 'tipo': '0', 'descricao': 'Comentário'},
            {'data': '08/10/2026', 'inicio': '09:00', 'fim': '10:00', 'tipo': '0', 'descricao': 'Outro'},
            {'data': '08/10/2026', 'inicio': '10:00', 'fim': '11:00', 'tipo': '0', 'descricao': 'Terceiro'}]}
        self.data = {'trabalhos': [self.work], 'edeskCredenciais': {'email': 'private', 'senha': 'private'}}

    def tearDown(self):
        self.auth.stop()
        self.env.stop()
        self.directory.cleanup()

    def test_confirmed_skipped_even_when_description_changes_and_accounts_isolated(self):
        key = journal.hour_key(self.work, self.work['horas'][0])
        journal.set_state('owner', [key], 'confirmed')
        self.work['horas'][0]['descricao'] = 'Texto alterado'
        prepared, selected, skipped = journal.prepare('owner', self.data)
        self.assertEqual(skipped, 1)
        self.assertEqual(len(prepared['trabalhos'][0]['horas']), 2)
        self.assertEqual(journal.prepare('other', self.data)[2], 0)
        self.assertNotIn('private', Path(self.directory.name, 'ledger.sqlite3').read_bytes().decode('latin1'))

    def test_partial_failure_preserves_confirmed_and_uncertain_without_blocking_unattempted(self):
        _, keys, _ = journal.prepare('owner', self.data)
        journal.set_state('owner', keys, 'pending')
        events = Path(self.directory.name) / 'events.jsonl'
        events.write_text('\n'.join(json.dumps(e) for e in [
            {'key': keys[0], 'state': 'started'}, {'key': keys[0], 'state': 'confirmed'},
            {'key': keys[1], 'state': 'started'}]), encoding='utf-8')
        self.assertEqual(journal.finish('owner', keys, events), 1)
        self.assertEqual(journal.states('owner'), {keys[0]: 'confirmed', keys[1]: 'uncertain'})
        with self.assertRaises(ValueError): journal.prepare('owner', self.data)
        self.assertEqual(journal.prepare('owner', self.data, True)[1], keys[1:])
        self.assertEqual(journal.prepare('owner', {'trabalhos': [{**self.work, 'horas': self.work['horas'][2:]}]})[1], keys[2:])

    def test_pending_after_restart_requires_review_and_duplicate_selection_rejected(self):
        _, keys, _ = journal.prepare('owner', self.data)
        journal.set_state('owner', keys, 'pending')
        with self.assertRaises(ValueError): journal.prepare('owner', self.data)
        self.work['horas'].append(dict(self.work['horas'][0]))
        with self.assertRaisesRegex(ValueError, 'repetidas'): journal.prepare('owner', self.data, True)

    def test_uncertain_requires_explicit_retry_without_launching_process(self):
        _, keys, _ = journal.prepare('owner', self.data)
        journal.set_state('owner', keys, 'uncertain')
        with patch('cloud_run.main.subprocess.Popen') as process:
            response = self.client.post('/api/edesk/horas', headers=HEADERS, json={'request': self.data, 'enviar': True})
            self.assertEqual(response.status_code, 409)
            process.assert_not_called()

    def test_manual_retry_sends_only_unconfirmed_and_finishes_without_block(self):
        _, keys, _ = journal.prepare('owner', self.data)
        journal.set_state('owner', keys[:1], 'confirmed')
        journal.set_state('owner', keys[1:2], 'pending')
        journal.set_state('owner', keys[2:], 'uncertain')
        def run(*args, **kwargs):
            data = json.loads(Path(args[0][-1]).read_text(encoding='utf-8'))
            hours = [hour for work in data['trabalhos'] for hour in work['horas']]
            self.assertEqual([hour['_sendKey'] for hour in hours], keys[1:])
            self.assertTrue(all(hour['_retryUnconfirmed'] for hour in hours))
            Path(kwargs['env']['EDESK_EVENTS_FILE']).write_text('\n'.join(
                json.dumps({'key': hour['_sendKey'], 'state': 'confirmed'}) for hour in hours))
            return process.return_value
        with patch('cloud_run.main.subprocess.Popen') as process:
            process.side_effect = run
            process.return_value.communicate.return_value = ('finished', '')
            process.return_value.returncode = 0
            response = self.client.post('/api/edesk/horas', headers=HEADERS,
                json={'request': self.data, 'enviar': True, 'retryUncertain': True})
            self.assertEqual(process.call_count, 1)
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json['confirmed'])
        self.assertEqual(journal.states('owner'), dict.fromkeys(keys, 'confirmed'))

    def test_exit_zero_alone_does_not_confirm_hour_and_progress_belongs_to_owner(self):
        def run(*args, **kwargs):
            path = Path(args[0][-1])
            data = json.loads(path.read_text(encoding='utf-8'))
            key = data['trabalhos'][0]['horas'][0]['_sendKey']
            Path(kwargs['env']['EDESK_EVENTS_FILE']).write_text(json.dumps({'key': key, 'state': 'started'}) + '\n')
            Path(kwargs['env']['EDESK_PROGRESS_FILE']).write_text('{"stage":"login"}')
            status = self.client.get('/api/edesk/status', headers=HEADERS).json
            self.assertEqual(status['operationId'], 'operation-test')
            self.assertEqual(status['stage'], 'login')
            with patch('local_edesk.authentication.verify_token', return_value={'sub': 'other'}):
                self.assertIsNone(self.client.get('/api/edesk/status', headers=HEADERS).json['operationId'])
            return process.return_value
        with patch('cloud_run.main.subprocess.Popen') as process:
            process.side_effect = run
            process.return_value.communicate.return_value = ('HTTP 200', '')
            process.return_value.returncode = 0
            response = self.client.post('/api/edesk/horas', headers=HEADERS,
                json={'request': self.data, 'enviar': True, 'operationId': 'operation-test'})
        self.assertEqual(response.status_code, 502)
        self.assertFalse(response.json['confirmed'])
        self.assertIn('aguardam conferência', response.json['message'])
        self.assertEqual(list(journal.states('owner').values()), ['uncertain'])

    def test_success_requires_confirmation_of_every_hour(self):
        for confirmed in [False, True]:
            with self.subTest(confirmed=confirmed):
                journal.delete('owner', list(journal.states('owner')))
                def run(*args, **kwargs):
                    data = json.loads(Path(args[0][-1]).read_text(encoding='utf-8'))
                    keys = [hour['_sendKey'] for work in data['trabalhos'] for hour in work['horas']]
                    if confirmed:
                        Path(kwargs['env']['EDESK_EVENTS_FILE']).write_text('\n'.join(
                            json.dumps({'key': key, 'state': 'confirmed'}) for key in keys))
                    return process.return_value
                with patch('cloud_run.main.subprocess.Popen') as process:
                    process.side_effect = run
                    process.return_value.communicate.return_value = ('finished', '')
                    process.return_value.returncode = 0
                    response = self.client.post('/api/edesk/horas', headers=HEADERS,
                        json={'request': self.data, 'enviar': True})
                self.assertEqual(response.status_code, 200 if confirmed else 502)
                self.assertEqual(response.json['confirmed'], confirmed)

    def test_manual_review_and_history_restore_never_downgrades_confirmed(self):
        _, keys, _ = journal.prepare('owner', self.data)
        response = self.client.post('/api/edesk/history', headers=HEADERS, json={'items': {keys[0]: 'confirmed'}})
        self.assertEqual(response.status_code, 200)
        self.client.post('/api/edesk/history', headers=HEADERS, json={'items': {keys[0]: 'uncertain'}})
        self.assertEqual(journal.states('owner')[keys[0]], 'confirmed')
        review = self.client.post('/api/edesk/review', headers=HEADERS, json={'request': self.data})
        self.assertEqual([i['state'] for i in review.json['items']], ['confirmed', 'new', 'new'])
        self.assertEqual(self.client.get('/api/edesk/history', headers={'Origin': HEADERS['Origin']}).status_code, 401)
        invalid = self.client.post('/api/edesk/history', headers=HEADERS, json={'items': {'invalid': 'confirmed'}})
        self.assertEqual(invalid.status_code, 400)
        automation_lock.acquire()
        try:
            self.assertEqual(self.client.post('/api/edesk/history', headers=HEADERS, json={'items': {keys[1]: 'confirmed'}}).status_code, 409)
        finally: automation_lock.release()


if __name__ == '__main__': unittest.main()
