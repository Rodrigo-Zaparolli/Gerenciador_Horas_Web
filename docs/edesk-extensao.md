# Integração E-Desk pelo navegador

Esta opção executa a automação no Chrome/Edge de cada computador que fará os envios. Não exige API oficial, servidor Python, computador central, domínio ou hospedagem adicional. O computador usado para enviar deve permanecer ligado durante aquela operação.

## Instalação

Abra https://gerenciador-horas.web.app/instalar-extensao.html, baixe o ZIP e siga os passos. Também pode carregar a pasta `browser_extension` diretamente no modo de desenvolvedor do navegador. Em cada computador que enviará, instale uma vez. Instalar a extensão exige ação do usuário no navegador; o site não pode fazer isso automaticamente.

Abra o E-Desk, entre na conta desejada e recarregue o app. A extensão instalada é detectada automaticamente e tem prioridade sobre integração local/central. Para voltar ao modo anterior, desative a extensão e recarregue o app.

Antes de executar, o app mostra a revisão e a extensão abre uma aba de confirmação. Clique em **Iniciar envio**. Se não houver sessão ativa, entre no E-Desk na aba aberta. MFA/CAPTCHA devem ser concluídos pelo usuário, sem tentativa de contorno.

## Segurança e confirmação

- A ponte aceita mensagens apenas dos dois domínios Firebase do app. A automação pode acessar apenas `https://promob.e-desk.com.br/`.
- A extensão usa a sessão do navegador; não recebe senhas do E-Desk nem tokens Firebase. Não envia dados para serviços de terceiros.
- Dados de uma operação ficam em `chrome.storage.session`; são apagados do registro após conclusão. O histórico local guarda apenas hash de identidade da hora e estado, separados pelo UID do app. Content scripts não podem ler o armazenamento da extensão.
- O UID organiza o histórico local; ele não substitui a autenticação do E-Desk. O usuário confere a conta do E-Desk antes de iniciar. Em computadores compartilhados, saia das duas contas ao terminar.
- Identificação de solicitação e trabalho exige número exato. Páginas antigas não são usadas como resultado de uma navegação nova.
- Horas confirmadas não são repetidas. Horas com tentativa de salvamento sem confirmação ficam incertas e exigem conferência ou autorização explícita de nova tentativa. A tabela do E-Desk também é verificada antes de enviar, inclusive se não houver histórico local.
- O texto de “Trabalho realizado” é preservado e o novo comentário é acrescentado abaixo. Alteração inesperada do texto interrompe o envio.
- Fases atualizam exclusivamente os nomes selecionados, com correspondência única. A confirmação exige recarregar a página e conferir as datas persistidas.
- Comentários são confirmados automaticamente apenas quando um novo texto aparece após recarregar a tela. Comentários com imagens requerem conferência manual de texto e imagens; a extensão não declara sucesso apenas porque o botão Salvar foi clicado.
- Fechar a aba de confirmação não cancela um salvamento já iniciado. O app recupera o estado como não confirmado e bloqueia novos envios simultâneos.
- O histórico é local ao navegador. Use o backup do app antes de limpar dados ou trocar de navegador. A extensão não sincroniza confirmações entre computadores.

## Limites e validação

Manifest V3, Chrome/Edge 120 ou superior, computador desktop. Não atende navegadores móveis. Comentários até 8 MB, incluindo imagens. Instalação manual sem loja; políticas de empresa podem bloquear modo de desenvolvedor.

Os testes usam páginas simuladas do E-Desk e não registram dados reais. Login, seletores e confirmação precisam ser validados no ambiente real com uma operação controlada pelo usuário. Mudanças na interface do E-Desk podem exigir atualização da extensão.

Para atualizar, substitua os arquivos da pasta instalada, clique em **Recarregar** na página de extensões e recarregue o app. `scripts/package_edesk_extension.py` cria o ZIP público apenas com os arquivos da extensão.

Referências: [Content scripts](https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts), [chrome.scripting](https://developer.chrome.com/docs/extensions/reference/api/scripting), [chrome.storage](https://developer.chrome.com/docs/extensions/reference/api/storage).
