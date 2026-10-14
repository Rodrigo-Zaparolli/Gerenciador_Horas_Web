# Aparência do aplicativo

O botão de tema no cabeçalho e nas telas de autenticação abre um menu com:

- **Claro:** fundo cinza-azulado (`#D5DFE9`), painéis `#E2E8EF`, texto azul-marinho.
- **Claro suave:** fundo `#DEE5EC`, painéis `#EBEFF3`, azul discreto `#236998`, sem branco puro.
- **Escuro:** fundo azul-marinho (`#0B1220`), painéis `#152235`, texto claro.

O tema claro é o padrão. A escolha é salva neste navegador (localStorage) ou no
diretório de suporte do app desktop. Não depende do Firebase nem da integração
E-Desk. Se o armazenamento estiver indisponível, a alternância continua funcionando
durante a sessão.

`AppAppearance` mantém a escolha e notifica os componentes existentes. A troca
preserva os States, rotas e controladores de campos. `AppPalette` reúne as cores
semânticas e `AppTheme` padroniza os componentes Material. A paleta antiga em
`cores_app.dart` usa esses mesmos valores para adaptar todas as telas.

As mudanças são de apresentação. Modelos, serviços, envio de horas, automação
E-Desk, leitura de arquivos e dados cadastrados foram preservados. As cores de
conteúdo dos comentários e das imagens do Excel não são recoloridas.

O acabamento usa `AppVisuals`: cards de 14 px de raio, bordas e sombras discretas,
ações de 40 px de altura e ícones de 18 px. Os três cards do dashboard continuam
compactos, com 260 px de altura. A navegação selecionada usa realce leve e
sublinhado. A tabela mantém seleção, status e alertas, com ações comuns neutras.
Os modais separam as ações do conteúdo e mantêm todos os campos e controles.

Validação: testes Flutter de aparência/estado, regressão dos fluxos existentes,
compilação web e `scripts/check_web_appearance.py` sem autenticar nem enviar dados.
