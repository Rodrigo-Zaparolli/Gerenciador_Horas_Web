"""Build the small hours-batch-14 update for an existing full installation."""
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
FILES = (
    'edesk_bot/edesk_horas.py',
    'edesk_bot/work_selection.py',
    'cloud_run/main.py',
    'scripts/start_full_integration.ps1',
)
README = '''ATUALIZAÇÃO hours-batch-14 — instalação completa já existente

Este arquivo não é uma instalação nova. Use a pasta que já contém
Iniciar integração E-Desk.cmd, python e os demais arquivos da integração.

1. Aguarde qualquer envio terminar.
2. Execute Parar integração E-Desk.cmd na instalação existente.
3. Extraia TODO o conteúdo deste ZIP nessa mesma pasta, substituindo
   os arquivos. Mantenha as subpastas edesk_bot, cloud_run e scripts.
   Não apague .edesk-local, python nem outros arquivos existentes.
4. Execute Iniciar integração E-Desk.cmd e atualize o app com Ctrl + F5.

Correção: localizar o trabalho exato na solicitação, aguardar a navegação
e reabrir o trabalho e o retroativo antes da próxima hora quando o E-Desk
voltar à solicitação ou fechar a tela após salvar. Apenas a navegação é
recuperada; o comando Salvar de uma hora anterior não é repetido.
O resultado só confirma o cadastro quando todos os apontamentos constarem
como confirmados. Os vínculos e o início automático são preservados.
'''


def main():
    target = ROOT / 'web/downloads/correcao-envio-horas-hours-batch-14.zip'
    target.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(target, 'w', ZIP_DEFLATED) as archive:
        for name in FILES:
            archive.write(ROOT / name, name)
        archive.writestr('LEIA-ME-ATUALIZACAO.txt', README.encode('utf-8-sig'))
    with ZipFile(target) as archive:
        assert archive.testzip() is None
        assert set(archive.namelist()) == {*FILES, 'LEIA-ME-ATUALIZACAO.txt'}
        for name in FILES:
            assert archive.read(name) == (ROOT / name).read_bytes()
    print(f'{target.name}: {target.stat().st_size} bytes; all source files verified')


if __name__ == '__main__':
    main()
