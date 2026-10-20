# Liberação dos novos ajustes

Conta designada pelo usuário: **rodrigozaparolli79@gmail.com**.

O novo menu de ações do projeto e o editor das abas Informações de entrada e
Checklist-Processo deverão ser disponibilizados inicialmente apenas para essa
conta autenticada. Manter a interface e os fluxos existentes para as demais
contas. Não liberar a todos sem nova orientação do usuário.

Usar `PilotFeatureAccess.allows` para verificar a conta ao apresentar e ao abrir
os novos recursos. A troca de conta deve retirar o acesso imediatamente; não
persistir um booleano global de liberação nem decidir pela máquina ou navegador.

Para futuras operações de gravação na planilha, verificar a mesma conta no
serviço usando as informações do token Firebase validado. Nunca aceitar um
e-mail informado no corpo da requisição como autorização. Continuar exigindo
autorização do vínculo de arquivo para o UID da conta.

A regra de liberação não constitui a implementação do editor nem habilita
gravações na planilha. As telas e a integração de edição serão implementadas
sob essa restrição. O original enviado para análise permanece inalterado.
