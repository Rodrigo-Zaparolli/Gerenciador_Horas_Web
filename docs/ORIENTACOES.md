# Imagens no conteúdo de Orientações

O editor mostra texto e imagens salvas dentro da seção **CONTEÚDO**, na mesma área de rolagem. Imagens coladas e selecionadas por **Adicionar imagem** aparecem em proporção original, com largura limitada ao editor, e podem ser ampliadas por clique ou removidas individualmente.

No navegador, **Ctrl + V** cola um print quando o campo de conteúdo está com foco. Também existe o botão **Colar print**. A imagem aparece imediatamente no conteúdo; o salvamento automático continua em segundo plano.

As imagens anteriores continuam disponíveis: a persistência usa o mesmo campo `imagens`, sem migração dos documentos existentes. A seleção de arquivo continua aceitando PNG, JPEG e WebP.

Validação: dois testes no Chrome verificam colagem com salvamento pendente e exibição/remoção de imagens preservando o texto. A análise da seção de Orientações não apresentou apontamentos.
