"""Exercise phase navigation and Telerik-like date controls without a real E-Desk."""
import os,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'edesk_bot'))
os.environ.setdefault('PLAYWRIGHT_BROWSERS_PATH',str(ROOT/'python/ms-playwright'))
from playwright.sync_api import sync_playwright
from phase_audit import read_phases, phase_dates, PhaseReadError

ROW="""<tr><td><span id="r_lblGFasNome">PROMOB - Implantacao</span></td>
<td><input type="hidden" id="r_txtGFasDtIniAj" value="2026-10-01"><input id="r_txtGFasDtIniAj_dateInput" value="01/10/2026"><input type="hidden" id="r_txtGFasDtIniAj_ClientState" value="{}"></td>
<td><input type="hidden" id="r_txtGFasDtTerAju" value="2026-10-30"><input id="r_txtGFasDtTerAju_dateInput" value="30/10/2026"><input type="hidden" id="r_txtGFasDtTerAju_ClientState" value="{}"></td></tr>"""
with sync_playwright() as p:
 browser=p.chromium.launch(headless=True,executable_path=p.chromium.executable_path)
 page=browser.new_page()
 def verify():
  data=read_phases(page)
  assert phase_dates(data,{'name':'Implantacao (OH)'})=={'start':'01/10/2026','end':'30/10/2026','phaseName':'PROMOB - Implantacao'}
 # Previously failed: hidden Telerik state inputs were counted as editable dates.
 page.set_content('<div id="cph1_rpvFasePro"><table>'+ROW+'</table></div>');verify()
 # An unrelated Fases text must not make the actual main tab ambiguous.
 page.set_content('<div>Fases</div><div class="rtsLevel rtsLevel1"><a class="rtsLink" href="#" onclick="document.querySelector(\'#cph1_rpvFasePro\').style.display=\'block\';return false"><span class="rtsTxt">Fases</span></a></div><div id="cph1_rpvFasePro" style="display:none"><table>'+ROW+'</table></div>');verify()
 # View can become visible before the AJAX reply populates its rows.
 page.set_content('<button role="tab" onclick="document.querySelector(\'#cph1_rpvFasePro\').style.display=\'block\'">Fases</button><div id="cph1_rpvFasePro" style="display:none;min-height:20px"></div>')
 page.evaluate('(row)=>setTimeout(()=>document.querySelector("#cph1_rpvFasePro").innerHTML="<table>"+row+"</table>",250)',ROW);verify()
 # Single phase need not have an extra wrapping row beneath the view.
 page.set_content('<div id="cph1_rpvFasePro">'+ROW.replace('<tr>','').replace('</tr>','').replace('<td>','').replace('</td>','')+'</div>');verify()
 # Two visible start inputs are ambiguous: do not guess one.
 page.set_content('<div id="cph1_rpvFasePro"><table>'+ROW.replace('</tr>','<td><input id="other_txtGFasDtIniAj" value="02/10/2026"></td></tr>')+'</table></div>')
 try:read_phases(page);raise AssertionError('Ambiguous controls accepted')
 except PhaseReadError as error:assert 'associacao unica' in str(error)
 # No main tab or phase view: explicit diagnostic, no Save attempt.
 page.set_content('<button>Trabalhos</button>')
 try:read_phases(page);raise AssertionError('Missing phases accepted')
 except PhaseReadError as error:assert 'aba principal' in str(error)
 browser.close()
print('PHASE_AUDIT_BROWSER_OK: 6 scenarios, hidden controls, main tab, AJAX wait, unique association; no live E-Desk')
