# Integração E-Desk em um computador central

O site continua em https://gerenciador-horas.web.app. Apenas o computador central
precisa do Python, dos scripts e do navegador da integração. Esta configuração
atende computadores na mesma rede privada, sem contratar hospedagem adicional.
O computador central deve ficar ligado, conectado e com a sessão do Windows aberta.
A janela do E-Desk e eventuais confirmações de login aparecem nele.

## Ativar

1. No computador que já tem a integração, execute `Iniciar central E-Desk.cmd`.
   Na primeira execução, use **Executar como administrador**, para criar uma regra
   de firewall limitada à porta 8765, ao Python do app, à sub-rede local e aos
   perfis Windows privado/domínio. O script não altera o perfil da rede.
2. Abra o app nesse computador e entre na sua conta.
3. Em **Integração E-Desk → Configurar central**, clique em
   **Autorizar este PC como central**. A autorização inicial só pode ser feita
   pelo próprio computador, com uma conta autenticada do app.
4. Nos outros computadores da mesma rede, abra o site e entre na mesma conta.
   O endereço da central é salvo na configuração da conta e carregado pelo app.
   Não instale a integração neles.
5. Quando o navegador solicitar, permita o acesso à rede local. Use Chrome ou Edge
   atualizado; outros navegadores podem exigir HTTPS para esta conexão.

Se houver mais de uma interface de rede, execute no PowerShell:

```powershell
.\scripts\start_edesk_central.ps1 -CentralAddress 192.168.1.10
```

Use o IPv4 real do computador central. Recomenda-se reservar esse endereço no
roteador. Se ele mudar, reinicie a central e autorize novamente no app usando a
conta responsável, para atualizar o endereço salvo na nuvem.

## Outras contas

Inicialmente somente a conta responsável pode enviar. Para permitir outra conta:

1. Nessa outra conta, abra **Configurar central** e copie o **ID desta conta**.
2. Na conta responsável, abra **Autorizar outra conta**, informe o ID e autorize.
3. Na outra conta, selecione **No computador central**, informe o mesmo endereço
   e salve. O app verifica a identidade do serviço e a autorização antes de salvar.

Cada conta mantém seu histórico separado. Os scripts usam pastas temporárias
distintas por execução; sessões, credenciais e resultados não são compartilhados
entre contas. Somente uma automação é executada por vez; outro envio recebe uma
mensagem para aguardar, sem ser repetido ou colocado numa fila escondida.

## Encerrar e retomar

Use `Parar integração E-Desk.cmd` no computador central. O script impede parada
enquanto um envio estiver em andamento. Após reiniciar o Windows, execute
`Iniciar central E-Desk.cmd` novamente. A autorização das contas é preservada em
`.edesk-local/central-access.json`, que não é publicada no site nem no Git.

Selecionar **Neste computador** e salvar no app muda a configuração dessa conta
para integração local em todos os navegadores. Não faz nenhum envio.

## Acesso fora da rede

Não encaminhe a porta 8765 diretamente para a internet. O modo central fornecido
escuta apenas no IPv4 privado escolhido e no loopback, valida origem e conta, e
rejeita clientes de redes públicas. O HTTP desta configuração destina-se a uma
rede privada de confiança; HTTPS é necessário para acesso externo.

O app também aceita uma URL HTTPS de integração, com caminho de base opcional.
Uma configuração externa exige um serviço ou gateway HTTPS próprio e ajuste
das restrições de rede/host, mantendo a autenticação e o isolamento de contas.
Essa infraestrutura externa não é provisionada por este instalador.

Referência do navegador: [Local Network Access no Chrome](https://developer.chrome.com/blog/local-network-access).
