# Liberação dos novos ajustes

Conta designada pelo usuário: **rodrigozaparolli79@gmail.com**.

O novo menu de ações do projeto e o editor das abas Informações de entrada e
Checklist-Processo estão implementados inicialmente apenas para essa
conta autenticada. Manter a interface e os fluxos existentes para as demais
contas. Não liberar a todos sem nova orientação do usuário.

Usar `PilotFeatureAccess.allows` para verificar a conta ao apresentar e ao abrir
os novos recursos. A troca de conta deve retirar o acesso imediatamente; não
persistir um booleano global de liberação nem decidir pela máquina ou navegador.

Para futuras operações de gravação na planilha, verificar a mesma conta no
serviço usando as informações do token Firebase validado. Nunca aceitar um
e-mail informado no corpo da requisição como autorização. Continuar exigindo
autorização do vínculo de arquivo para o UID da conta.

O serviço exige token da conta designada com identidade validada pelo Firebase e autorização
prévia do arquivo para o UID. A interface é liberada pela conta autenticada;
o serviço faz uma segunda validação independente antes de acessar a planilha.

Uso: Planilha → Editar no sistema. Requer Microsoft Excel instalado e integração
spreadsheet-dates-22 neste computador. Somente XLSX e XLSM de até 25 MB com as
abas e cabeçalhos esperados. Alterações ainda não salvas exigem confirmação
antes de descartar. Falha ou resposta incerta exige recarregar para conferir.

O serviço calcula em cópia com macros desativadas e preserva o pacote original,
incorporando apenas células editadas e caches calculados. Fórmulas, VBA,
imagens e controles não são substituídos pelos componentes regravados pelo
Excel. Backup anterior à troca fica em .gerenciador-backups ao lado do original.
Um arquivo aberto no Excel deve ser fechado antes de confirmar a gravação.

As macros dos botões da planilha não são executadas automaticamente. Alterar
produtos não executa Atualizar Planilha de Implantação; usar esse botão no Excel
quando necessário. O arquivo enviado para análise não foi modificado pelos testes.

Desde spreadsheet-dates-22, a leitura aceita datas como números do Excel,
texto brasileiro ou ISO. Instruções do modelo são exibidas como texto sem
alterar as células automaticamente nem impedir a abertura da planilha.
