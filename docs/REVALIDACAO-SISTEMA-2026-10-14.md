# Revalidação do sistema — 14/10/2026

Nova execução completa após as correções da revisão anterior. As execuções interrompidas durante a conversa não foram consideradas como testes aprovados; as verificações abaixo foram concluídas novamente.

| Verificação | Resultado |
| --- | --- |
| Suíte Flutter completa | 280 testes passaram; um teste exclusivo de navegador é ignorado nesta plataforma |
| Chrome: editor de horas, prévia e imagens | 10 testes passaram, incluindo o teste de colagem ignorado acima |
| Integrações Python | 46 testes passaram |
| Núcleo JavaScript da extensão | 7 testes passaram |
| Site público | Login e abertura/retorno do cadastro passaram em desktop e celular, sem erros JavaScript |
| Temas | 11 temas passaram em desktop e celular, com persistência após atualizar a página |
| Arquivos no navegador | Seleção/criação de pasta, leitura de arquivo, persistência, cancelamento e isolamento passaram |
| Extensão no navegador | Horas, fases selecionadas, comentários, deduplicação, falha ao salvar e interrupção passaram em páginas fictícias |
| Pacote Windows | Runtime, navegador, serviço, capacidade Excel e rejeição de chamadas sem autenticação passaram |
| Excel instalado | Duas planilhas sintéticas foram espelhadas e os arquivos originais permaneceram iguais |
| Análise Dart | Zero erros e zero apontamentos de contexto assíncrono; permanecem 28 avisos e 198 informações de manutenção |
| Publicação | Manifesto e aplicação pública conferidos; versão `e464dbf05bc84018b13d1b04e2247021` |

## Problema adicional encontrado e corrigido

O Dockerfile e a lista de arquivos permitidos no contexto Docker estavam desatualizados. Eles excluíam `comment_percentage.py`, `phase_confirmation.py`, `send_progress.py` e os módulos `central.py`/`journal.py` de `local_edesk`, apesar de o backend importá-los.

Os módulos foram incluídos explicitamente. O novo teste `test/test_container_sources.py` monta a mesma seleção de arquivos em uma pasta isolada, verifica as inclusões e importa os bots/backend. Também verifica o health em modo cloud e a rejeição de requisição sem autenticação. O Firebase Admin é simulado nesse teste, sem credenciais ou chamadas externas; sua instalação continua declarada em `cloud_run/requirements.txt`.

Nenhum container foi implantado e a imagem Linux não foi construída nesta revisão. A mudança corrige o pacote de fontes para uma futura construção; não altera a integração local instalada nem a versão do executável.

## Limites da revisão

Não foram feitos envios reais ao E-Desk, criação de contas reais, gravações/restaurações no Firebase de produção ou envio de e-mails. Esses cenários ainda precisam de ambiente ou contas de teste próprios. Os testes cobrem a suíte disponível e os fluxos controlados; não certificam 100% dos cenários possíveis nem variações externas do portal.

O teste Chrome precisou receber os recursos CanvasKit locais no navegador isolado para contornar o 404 conhecido do servidor de testes do SDK. O site público carregou normalmente.

## Publicação no GitHub

O projeto web foi preparado como um histórico inicial limpo para `Rodrigo-Zaparolli/Gerenciador_Horas_Web`, sem importar o histórico antigo que rastreava perfis de navegador. Código, testes, documentos e recursos visuais são incluídos. Credenciais, bancos locais, perfis, caches, backups, runtimes e arquivos compilados são excluídos.

O outro projeto executável e o repositório antigo são preservados.

Evidências locais: `build/github-web-final-tests.txt`, `build/github-web-final-chrome.txt`, `build/github-web-final-python.txt`, `build/github-web-final-analysis.txt`, `build/github-web-final-browser.txt`, `build/github-web-final-themes.txt`, `build/github-web-final-extension-browser.txt`, `build/github-web-final-package.txt`, `build/github-web-final-files.txt` e `build/github-web-final-excel.txt`.
