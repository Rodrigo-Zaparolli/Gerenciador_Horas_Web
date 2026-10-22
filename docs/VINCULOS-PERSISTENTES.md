# Pastas e planilhas entre atualizações — v41

A escolha de pastas e planilhas de projetos usa a integração local. Uma falha na detecção do serviço não muda silenciosamente para o seletor do navegador, que não fornece o caminho completo do Windows. Sem o serviço, o app informa o problema e preserva o campo existente.

O projeto guarda no Firebase a referência com conta, tipo de recurso e caminho completo. A integração emite uma assinatura HMAC ligada a esses três valores. A chave privada permanece em `%LOCALAPPDATA%\GerenciadorHoras\integracao\local-files.sqlite3.key`, fora da pasta extraída, e não é enviada ao navegador ou incluída nos pacotes. Atualizações não substituem essa chave.

O índice SQLite continua nesse mesmo diretório do perfil do Windows, com a cópia de recuperação já existente. Se o índice e sua cópia forem perdidos, a assinatura permite reconstruir somente autorizações emitidas neste computador para essa conta e caminho. Alterar o endereço, a conta, o tipo ou o identificador não cria permissão. O fato de uma pasta existir ou ter o mesmo nome não a autoriza. Índices ilegíveis reconhecidos são preservados com sufixo `.corrupt-...`; a recuperação usa a cópia local ou as referências assinadas. Um índice antigo danificado não impede o uso dos vínculos atuais.

Referências antigas ainda autorizadas são convertidas ao abrir. O app grava o resultado no documento real do projeto, incluindo cadastros antigos com identificador de documento diferente da solicitação. A operação confirma a gravação; não informa sucesso quando não encontra o registro ou quando o vínculo mudou em outra tela. Se apenas a identidade da planilha mudou, o snapshot já carregado acompanha o novo vínculo, preservando seu conteúdo.

A movimentação confirmada de projetos emite referências assinadas para os destinos. Os registros de outros projetos são preservados. Os caminhos continuam separados por usuário e projeto; nenhum vínculo é associado apenas por nomes como `Documentos` ou `Projeto.xlsm`.

## Aplicação e limites

Atualize a integração para v41 e reinicie-a. A atualização leve deve substituir os arquivos da instalação existente, preservando `.edesk-local` e os dados do perfil do Windows. O pacote completo também está disponível. O início automático e os iniciadores avulsos passam a reconhecer o protocolo atual, evitando reiniciar um serviço compatível por uma comparação com o protocolo antigo.

No mesmo PC e usuário do Windows, referências já convertidas sobrevivem à troca de pasta do pacote e à perda do índice, enquanto a chave permanecer no perfil. Arquivos movidos fora do sistema, outro computador, exclusão completa dos dados do perfil ou vínculos antigos sem qualquer autorização recuperável podem exigir uma seleção inicial. O app não deve recriar permissões somente a partir de um texto enviado pela web.

## Verificação

Os testes usam arquivos temporários e banco Firebase em memória: duas extrações distintas e novos processos Python; remoção do índice e da cópia; índice danificado preservado; pastas e planilhas homônimas de projetos diferentes; migração de referências antigas; rejeição de caminho, conta, tipo ou identificador adulterados; gravação em documentos legados; preservação do snapshot; concorrência e movimentação de finalizados. Não abrem arquivos reais do usuário nem alteram projetos reais.
