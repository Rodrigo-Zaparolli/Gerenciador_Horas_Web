# BETA — piloto pessoal

A interface e o serviço de áudio são habilitados somente para a conta piloto
`rodrigozaparolli79@gmail.com`, autenticada pelo Firebase. O controle é próprio
da BETA: `PilotFeatureAccess.allows` permanece como estava para outros recursos.
Não há nova coleção, mudança de regra do Firestore ou migração de dados.

## Preparação local

Na pasta da integração completa, execute `scripts/setup_beta_voice.ps1`.
Ele prepara dependências e modelos em `.edesk-local/beta-voice`, separados do
Python principal. Os modelos são baixados de seus projetos oficiais. Depois,
reinicie a integração quando nenhuma operação estiver em andamento.
O pacote da integração precisa conter `local_edesk/beta_voice.py` e a rota nova
de `cloud_run/main.py`. A interface web e a integração precisam ser atualizadas
juntas; o código antigo da integração não oferece `/api/beta-voice`.

Áudio: Vosk em português e Kokoro/Dora, locais. Nenhum áudio é salvo por padrão.
Há cache limitado de falas em memória. A validação do login Firebase, consultas
ao Firestore e o envio ao E-Desk continuam dependendo de internet.

## Uso

1. Ative a escuta pelo ícone do microfone no cabeçalho. Ela não é ativada ao abrir o sistema.
   O painel e o holograma permanecem ocultos nesse momento.
2. Diga “Olá, Beta”. A saudação segue o horário local. Somente então aparecem
   o balão de conversa e o holograma flutuante abaixo, sem fundo de cartão.
3. Diga “Enviar horas do dia”. A BETA abre Tarefas e consulta registros reais.
4. Escolha “Pode ler” ou “Conferir na tela”.
5. Após conferir, diga “Pode enviar”. A BETA relê os dados no servidor e
   interrompe o envio se algum registro mudou. O envio reutiliza a rotina
   existente, incluindo validação de referências e confirmação da integração.
6. “Fechar Beta” recolhe a interface; “Desativar escuta” encerra o microfone.

Depois do envio, a BETA fala o resultado confirmado, diz “Qualquer coisa, é só
me chamar” e se recolhe. A escuta explicitamente ativada permanece ligada.
Falhas são informadas como falhas, sem anunciar sucesso não confirmado.

A confirmação “Sim” depois da oferta de conferência inicia a preparação;
ela não autoriza envio. Para autorizar, use “Pode enviar” após escolher a
conferência. Leitura, carregamento e envio bloqueiam comandos concorrentes.
O botão Parar voz permite interromper a leitura e revisar na tela.

A escuta não é encerrada ao minimizar ou trocar de aba. Ainda depende de o
navegador continuar executando a página; suspensão, descarte da aba, fechamento
do navegador e suspensão do PC interrompem seu funcionamento. Não é um serviço
de escuta independente do Windows.

## Validação e publicação

Testes de áudio e autorização não enviam horas reais. A versão deve ser compilada
novamente antes da publicação. Implementar o piloto não publica o site e não
atualiza automaticamente integrações já instaladas.

## Publicação pessoal

O site mantém duas compilações no mesmo domínio: a estável na raiz e a pessoal
em `/piloto/`. `redirectPilotAccount` encaminha a conta autorizada para o piloto;
outras contas que abrirem esse endereço retornam à raiz. A versão estável mantém
o comportamento anterior, recebendo apenas esse encaminhamento. O serviço de
voz valida novamente o token Firebase e a conta, independentemente da interface.

Compile o piloto com `scripts/build_web_release.ps1 -BaseHref /piloto/ -PersonalPilot`.
A versão estável deve partir da base publicada preservada, acrescida somente dos
arquivos `pilot_route*` e da chamada a `redirectPilotAccount` no início da navegação.
Use `scripts/assemble_personal_hosting.py --stable CAMINHO_DA_COMPILACAO_ESTAVEL`
para montar `build/personal-hosting`, destino configurado no Firebase Hosting.
O montador exige destino novo, valida os identificadores e mantém os instaladores
compartilhados na raiz, sem duplicá-los no piloto. Publique somente Hosting;
esta entrega não altera regras ou dados do Firestore.
