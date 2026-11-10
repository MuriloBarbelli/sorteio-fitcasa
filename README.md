# Sorteio dos Salões de Festas · Fit Casa Rio Bonito

Página pública do sorteio das reservas dos Salões 1 e 3 para o Natal (24 e 25/12) e o Ano Novo (31/12 e 01/01).

Qualquer pessoa pode abrir a página e acompanhar a lista de inscritos e os resultados. Só a sindicatura, com login, publica a lista e conduz o sorteio.

## Regras do sorteio

1. A reserva de cada data é única e vale para os dois dias, com uma única taxa de uso.
2. Uma unidade pode ganhar no Natal e no Ano Novo, mas não os dois salões na mesma data.
3. Ordem: Natal Salão 1, Natal Salão 3, Ano Novo Salão 1, Ano Novo Salão 3. Quem ganha o Salão 1 sai do sorteio do Salão 3 daquela data.
4. As demais unidades formam a lista de espera, na ordem sorteada.

## Como o sorteio é feito

- A vencedora é escolhida com `crypto.getRandomValues`, o gerador aleatório do navegador, com chance igual para todas as unidades aptas. A lista de espera é embaralhada da mesma forma.
- A roleta é só a apresentação do resultado: todas as unidades aparecem o mesmo número de vezes e ela para na sorteada.
- O código está todo em `index.html`. As funções que decidem o resultado são `aleatorio`, `embaralhar` e `sortear`.

## Garantias do banco de dados

Os dados ficam no Supabase. As regras abaixo valem no servidor, não dependem da página (veja `banco.sql`):

- Qualquer pessoa pode ler a lista e os resultados. Só o administrador grava.
- Cada sorteio só pode ser gravado uma vez. Não existe permissão para alterar ou apagar um resultado.
- Os sorteios precisam seguir a ordem, e o vencedor precisa estar inscrito naquele sorteio.
- A lista de inscritos não pode ser trocada depois do primeiro sorteio.
- O horário de cada sorteio é o do servidor, não o do computador de quem sorteou.
