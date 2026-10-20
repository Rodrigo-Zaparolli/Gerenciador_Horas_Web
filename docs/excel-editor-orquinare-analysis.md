# Editor da planilha — análise das duas abas

Arquivo analisado: Orquinare Planejados.xlsm. Leitura somente; nenhum salvamento
do original, execução de macro ou consulta ao vínculo externo foi realizado.

## Informações de entrada

Proposta de tela: formulário dividido em Projeto e produtos, Datas, Sistema,
Cliente, Equipe Cyncly e Materiais. Valores pessoais e senhas do arquivo não
estão reproduzidos neste documento.

Mapeamento inicial desta versão do modelo:

| Grupo | Células |
|---|---|
| Solicitação e tipo do projeto | C2:C3 |
| Produtos e serviços, Sim/Não | B5:B17; rótulos em C5:C17 |
| Proposta, recebimento e encerramento | C22:C24 |
| Dados do sistema e biblioteca | C27:C32 |
| Senhas do sistema | C35:C37 |
| Materiais e liberação do sistema | C39:C40 |
| Equipe do cliente | F18:I21 |
| Cadastro comercial do cliente | F23:F29 e H23:H29 |
| Acesso ao Prices | F32, H32, F33, H33 |
| Equipe Cyncly | F37:H48 |

G37 contém uma fórmula de busca do e-mail do consultor. Não deve ser substituída
por texto pelo editor. Cada endereço precisa ser validado contra os rótulos do
modelo aberto; outras planilhas podem ter linhas diferentes.

## Checklist-Processo

Tabela estruturada `Tab_Check_List`, intervalo C16:AA223.
Há 159 linhas com descrição de tarefa e percentual preenchido; a tabela contém
também separadores e títulos. Não tratar todas as linhas como tarefas editáveis.

As seis etapas são Gerência de Projetos, Contato Inicial, Levantamento de Escopo,
Desenvolvimento, Implantação e Pós-Implantação.

Proposta de tela: etapas expansíveis, busca de tarefa e filtros de pendentes e
concluídas. Exibir a descrição, percentual, tempo estimado e link/observação.

O percentual de tarefa está na coluna E. A validação existente permite
0%, 25%, 50%, 75% e 100%; salvar os valores numéricos 0, 0.25, 0.5, 0.75 e 1.
Respeitar o domínio da validação de cada linha, pois nem todas têm a mesma regra.

As colunas D, F, G, H, I e J trazem trabalho, descrição, TAG, estimativa,
subtrabalho e referência. Descrição e observação aparecem bloqueadas no modelo,
embora a aba não esteja protegida. A primeira versão deve preservar esses campos
e editar os percentuais; ampliar os campos editáveis é uma decisão de produto.

Foram identificadas 3.565 fórmulas nesta aba, inclusive cálculos nas colunas
ocultas K:AA. Mantê-las no Excel e ler os resultados recalculados.

## Gravação proposta

Usar o arquivo já vinculado ao projeto e a integração de Excel existente.
O aplicativo deve encaminhar uma lista explícita de alterações: aba, célula,
valor lido originalmente e novo valor. O serviço deve conferir o arquivo e os
valores atuais para impedir sobrescrita de mudanças feitas no Excel entre a
leitura e o salvamento.

Antes da gravação: criar cópia de segurança; validar modelo, tipos, permissões e
ausência de fórmulas nos destinos. Gravar apenas os destinos permitidos, salvar
mantendo o formato XLSM, recalcular e reler para conferir os valores.
Retornar confirmação somente após essa conferência. Não executar novamente
um salvamento cuja resposta ficou incerta sem antes consultar o arquivo.

O pacote contém VBA, controles e um vínculo externo. Não substituir o arquivo
por uma exportação de planilha nova. A edição via automação do Excel deve ser
validada em cópia antes de liberar a escrita no original.

O botão Atualizar Planilha de Implantação está associado a `Atualiza_PL_Prj`.
Existem também botões de busca de solicitação, razão social, CNPJ e CEP.
O corpo dessas macros não foi analisado nem executado nesta leitura. Portanto,
não é possível afirmar ainda quais podem ser acionadas automaticamente; salvar
células e executar esses botões são funcionalidades distintas.

Foi encontrado um nome definido legado com `#REF!` (`PLPR_Data`). A análise não
estabelece se ele participa das duas telas solicitadas. Não corrigi-lo nem
reatribuir uma referência sem verificar seu uso no modelo.

## Critérios de aceite antes de editar o original

1. Trabalhar em cópia com macros desativadas durante a inspeção inicial.
2. Alterar um campo textual, uma data, um Sim/Não e um percentual de tarefa.
3. Reabrir no Excel e conferir valores, fórmulas, totais, VBA, botões e imagens.
4. Verificar concorrência: mudança feita diretamente no Excel deve bloquear
   sobrescrita silenciosa pelo app.
5. Validar o comportamento dos botões/macros separadamente antes de automatizá-los.

Esta entrega é o mapeamento e a proposta; o editor e a gravação ainda não foram
implementados.
