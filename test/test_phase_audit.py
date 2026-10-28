import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'edesk_bot'))
from phase_audit import phase_key,phase_dates,summarize_work

class PhaseAuditTests(unittest.TestCase):
 def test_phase_match_requires_exact_normalized_name(self):
  phases={phase_key('PROMOB - Implanta\u00e7\u00e3o Plugin'):{'name':'PROMOB - Implanta\u00e7\u00e3o Plugin','start':'05/10/2026','end':'20/10/2026'}}
  self.assertEqual(phase_dates(phases,{'name':'Implantacao Plugin (OH)'})['start'],'05/10/2026')
  with self.assertRaises(ValueError):phase_dates(phases,{'name':'Implantacao'})
 def test_balance_requires_both_proven_values(self):
  for values,expected in [({'estimatedHours':'10:00','hours':'02:30'},('07:30','00:00')),({'estimatedHours':'02:00','hours':'03:15'},('00:00','01:15')),({'estimatedHours':'00:00','hours':'00:00'},('00:00','00:00'))]:
   summarize_work(values);self.assertEqual((values['remainingHours'],values['overrunHours']),expected)
  for values in [{'estimatedHours':'10:00'},{'hours':'02:30'},{'estimatedHours':'10:99','hours':'01:00'}]:
   summarize_work(values);self.assertNotIn('remainingHours',values)
 def test_completion_comes_from_status_not_percent_or_balance(self):
  for status in ['Conclu\u00edda','TRAB_FIM','Finalizado']:
   values={'status':status};summarize_work(values);self.assertEqual(values['completed'],'Sim')
  values={'status':'Em andamento','percentage':'100','estimatedHours':'01:00','hours':'02:00'}
  summarize_work(values);self.assertEqual(values['completed'],'Nao')
  values={'status':'Desconhecido','percentage':'100'};summarize_work(values);self.assertNotIn('completed',values)

if __name__=='__main__':unittest.main()
