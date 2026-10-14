# Pastas e arquivos locais na web

No editor, **Selecionar pasta** abre o seletor de diretórios do Chrome/Edge no computador. **Criar pasta** pede uma pasta de destino e cria a subpasta `ID - Cliente` após autorização de escrita pelo navegador. **Selecionar arquivo** vincula um documento local sem exigir Firebase Storage ou enviar seus conteúdos à nuvem.

O app guarda uma referência e a autorização local no navegador. Por segurança, a API do navegador fornece o nome e o acesso autorizado, não o caminho absoluto `C:\...`. O cadastro do projeto sincroniza a referência; o acesso aos arquivos continua específico do navegador e computador onde a seleção ocorreu. Em outro computador, selecione novamente ou use um link compartilhado de OneDrive, SharePoint, Drive etc.

Com **Iniciar abertura local.cmd** ativo, clique na pasta na tabela para abri-la no Explorador do Windows, ou na planilha para abrir o original no Excel/programa padrão, sem download. Vínculos antigos do navegador precisam localizar o original uma vez. Veja [Abrir os arquivos originais](abertura-local.md). Seleções novas com a integração ativa são vinculadas diretamente ao computador. Planilhas vinculadas também podem ser usadas na prévia do comentário.

O acesso pode exigir nova autorização após reiniciar o navegador. Limpar os dados do site remove os vínculos locais. Arquivos movidos ou removidos exigem nova seleção. O limite por arquivo é 25 MB e a listagem limita-se a 2.000 itens por pasta.

Em navegadores sem File System Access, a seleção de arquivo usa o seletor tradicional e guarda uma cópia local no navegador; alterações posteriores no original exigem nova seleção. Para pastas, use Chrome/Edge no computador ou informe um link compartilhado. A extensão E-Desk não é necessária para selecionar arquivos/pastas.

Referência: [File System Access API](https://developer.chrome.com/docs/capabilities/web-apis/file-system-access).
