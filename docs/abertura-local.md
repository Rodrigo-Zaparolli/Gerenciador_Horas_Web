# Abrir os arquivos originais no Windows

Execute **Iniciar abertura local.cmd** na pasta deste aplicativo, no computador onde estão as pastas e planilhas. O comando usa a integração local existente; não depende de computador central nem tem assinatura ou hospedagem paga. Se a versão anterior estiver ativa, será atualizada somente quando não houver envio E-Desk em andamento.

Recarregue https://gerenciador-horas.web.app com Ctrl+F5. No editor, selecionar pasta ou arquivo com a integração ligada cria um vínculo com o original do Windows. Na tabela, a pasta abre no Explorador e a planilha no programa padrão do Windows, normalmente Excel. Nenhuma cópia é baixada. Configure o programa padrão para `.xlsx`/`.xlsm` no Windows se necessário.

Quando o Chrome/Edge solicitar acesso à rede local ou a este dispositivo, escolha **Permitir**. Se o acesso foi bloqueado anteriormente, use o ícone à esquerda do endereço do site → permissões/configurações do site → acesso à rede local/este dispositivo → **Permitir** e recarregue. O app aguarda a resposta à permissão; uma verificação automática não cancela essa solicitação.

Vínculos criados anteriormente pelo navegador pedem para localizar o original uma única vez ao abrir. Selecione a pasta ou arquivo com o mesmo nome; o caminho aprovado fica registrado apenas neste computador, separado por conta. O navegador não disponibiliza o caminho absoluto de seus vínculos antigos.

Em outro computador, execute a integração local naquele computador e selecione os originais disponíveis nele. A extensão E-Desk continua funcionando independentemente desta integração. Sem integração local, o editor ainda permite vincular arquivos pelo navegador, mas a abertura no Excel/Explorador precisa do componente local.

O serviço aceita somente requisições autenticadas das origens do aplicativo e pelo endereço de loopback. Caminhos arbitrários enviados pelo navegador não são executados; somente documentos e pastas escolhidos na janela do Windows podem ser abertos. A interface de abertura não fica disponível pela rede da central.
