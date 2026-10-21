import unittest
from edesk_bot.hour_receipt import date_value, time_value, presence, deliver_hours


def hour(start='08:00', end='09:00', kind='0'):
    return {'data': '21/10/2026', 'inicio': start, 'fim': end, 'tipo': kind}


class HourReceiptTests(unittest.TestCase):
    def test_grid_date_and_time_formats_are_normalized_but_invalid_values_are_rejected(self):
        self.assertEqual(date_value('21/10/26'), '21/10/2026')
        self.assertEqual(time_value('8:00:00'), '08:00')
        self.assertIsNone(date_value('31/02/2026'))
        self.assertIsNone(time_value('08:00:01'))
        self.assertIsNone(time_value('24:00'))

    def test_presence_matches_type_and_never_treats_unknown_or_other_type_as_absent(self):
        item = hour()
        self.assertEqual(presence({'rows': [hour(kind='Interno')], 'complete': True}, item), 'present')
        self.assertEqual(presence({'rows': [hour(kind='Externo')], 'complete': True}, item), 'occupied')
        self.assertEqual(presence({'rows': [], 'complete': False}, item), 'unknown')
        self.assertEqual(presence({'rows': [], 'complete': True}, item), 'absent')

    def run_delivery(self, items, read, save):
        events, stages = [], []
        result = deliver_hours(items, read, save, lambda h, s: events.append((h, s)), stages.append)
        return result, events, stages

    def test_existing_and_successful_hours_are_not_repeated_and_only_missing_is_retried(self):
        items = [hour(), hour('09:00', '10:00'), hour('10:00', '11:00')]
        records, calls = [items[0]], []
        def save(item, index, retry):
            calls.append((index, retry))
            if index != 3 or retry:
                records.append(item)
            return 'completed'
        result, events, stages = self.run_delivery(items,
            lambda: {'rows': list(records), 'complete': True}, save)
        self.assertTrue(result['ok'])
        self.assertEqual(calls, [(2, False), (3, False), (3, True)])
        self.assertEqual(len(records), 3)
        self.assertEqual(result['verified'], 3)
        self.assertEqual(result['retried'], 1)
        self.assertTrue(all(state == 'confirmed' for _, state in events))
        self.assertIn('retrying', stages)

    def test_late_first_commit_is_found_in_second_read_and_not_submitted_again(self):
        item, calls = hour(), []
        reads = 0
        def read():
            nonlocal reads
            reads += 1
            return {'rows': [item] if reads >= 3 else [], 'complete': True}
        result, _, _ = self.run_delivery([item], read,
            lambda h, i, retry: calls.append(retry) or 'completed')
        self.assertTrue(result['ok'])
        self.assertEqual(calls, [False])
        self.assertEqual(result['retried'], 0)

    def test_uncertain_post_that_committed_is_confirmed_by_grid_without_repeat(self):
        item, records, calls = hour(), [], []
        def save(h, i, retry):
            calls.append(retry)
            records.append(h)
            return 'unknown'
        result, _, _ = self.run_delivery([item], lambda: {'rows': list(records), 'complete': True}, save)
        self.assertTrue(result['ok'])
        self.assertEqual(calls, [False])

    def test_uncertain_missing_post_is_never_retried(self):
        calls = []
        result, events, _ = self.run_delivery([hour()], lambda: {'rows': [], 'complete': True},
            lambda h, i, retry: calls.append(retry) or 'unknown')
        self.assertFalse(result['ok'])
        self.assertEqual(calls, [False])
        self.assertEqual(result['uncertain'], 1)
        self.assertEqual(events, [])

    def test_retry_is_bounded_and_definitely_missing_hours_are_released(self):
        calls = []
        result, events, _ = self.run_delivery([hour()], lambda: {'rows': [], 'complete': True},
            lambda h, i, retry: calls.append(retry) or 'completed')
        self.assertFalse(result['ok'])
        self.assertEqual(calls, [False, True])
        self.assertEqual(result['missing'], 1)
        self.assertEqual(events[0][1], 'not_submitted')

    def test_unreadable_or_filtered_grid_never_allows_a_blind_send_or_retry(self):
        for snapshot in ({'rows': [], 'complete': False}, {'rows': [hour(kind='1')], 'complete': True}):
            calls = []
            result, _, _ = self.run_delivery([hour()], lambda: snapshot,
                lambda *args: calls.append(args) or 'completed')
            self.assertFalse(result['ok'])
            self.assertEqual(calls, [])

    def test_pre_submission_failure_can_be_retried_without_a_second_initial_save(self):
        records, calls = [], []
        def save(h, i, retry):
            calls.append(retry)
            if retry: records.append(h)
            return 'completed' if retry else 'not_submitted'
        result, _, _ = self.run_delivery([hour()], lambda: {'rows': list(records), 'complete': True}, save)
        self.assertTrue(result['ok'])
        self.assertEqual(calls, [False, True])


if __name__ == '__main__': unittest.main()
