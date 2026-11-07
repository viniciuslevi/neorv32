# Registro de Depuração — Bring-up em Hardware Real

Relato do ciclo de depuração que levou o sistema de uma inferência incorreta a uma
inferência bit-exata em relação à referência. Organizado em estado inicial,
problemas identificados, hipóteses levantadas, soluções aplicadas e estado final.

As hipóteses descartadas estão registradas junto com as confirmadas. Elas custaram
tempo e produziram evidência útil, e omiti-las daria a impressão de um caminho
linear que não existiu.

---

## 1. Estado inicial

O projeto integrava o processador NEORV32 (RV32IMC), um acelerador sistólico 8×8
INT8 e um controlador de SDRAM próprio, sintetizados para o EP4CE115F29C7 da placa
DE2-115. A cadeia completa já executava: o firmware recebia pesos e imagem pela
UART, gravava na SDRAM, percorria as quatro camadas da rede convolucional e
imprimia a classe prevista.

O que funcionava:

- Síntese sem erros, com o analisador de timing reportando folga de 5,49 ns.
- Duas testbenches VHDL passando em GHDL — 64 de 64 resultados corretos no matmul
  8×8×8, e escrita/leitura íntegra no controlador de SDRAM contra um modelo de
  chip, inclusive atravessando um ciclo de *refresh*.
- O teste isolado do acelerador (`test_systolic_accel`) reportando aprovação.
- Geração de pesos e metadados de quantização a partir do modelo treinado.

O que não funcionava, e estava registrado como investigação pendente:

- **Classe prevista incorreta.** Os logits finais apresentavam valores empatados no
  máximo representável em INT8, sugerindo saturação em algum estágio.
- **Divergência entre software e hardware.** O benchmark que compara um matmul
  8×8×8 calculado na CPU com o mesmo cálculo no acelerador reportava os 64
  elementos divergentes — nenhum coincidia.

A suspeita documentada apontava para a camada de mais alto nível do driver do
acelerador, especificamente o preenchimento de borda ou a correção de zero-point.

---

## 2. Problemas identificados

### 2.1 Corrupção sistemática na SDRAM

O firmware possuía um teste de sanidade que gravava dezesseis bytes e os relia.
Ele acusava divergência, mas apenas isso: informava *que* havia erro, não onde nem
de que tipo.

Um teste mais informativo revelou um padrão até então invisível. Escrevendo
padrões fixos — `0x00000000`, `0xFFFFFFFF`, `0xAAAAAAAA`, `0x55555555` — em 256
palavras de 32 bits, em quatro regiões distintas da memória, o resultado era zero
erros. Escrevendo o próprio endereço como dado, o resultado era 256 palavras
erradas de 256, em todas as regiões.

A explicação dessa assimetria é o achado metodológico central do episódio:
**padrões uniformes são cegos a erros de endereçamento**. Se toda posição de
memória contém o mesmo valor, ler da posição errada devolve o valor correto, e o
teste passa. Somente dados únicos por palavra expõem o defeito.

### 2.2 O acelerador devolvia resultados obsoletos

O benchmark reportava os 64 elementos divergentes desde o início do projeto.
Impressos os valores, apareceu estrutura: a coluna zero do resultado de hardware
era constante nas oito linhas, enquanto a mesma coluna do resultado de software
variava. O índice da linha não estava alcançando o resultado.

### 2.3 O relatório de timing não cobria a interface crítica

O arquivo de restrições do projeto continha quatro linhas e declarava apenas o
clock de sistema. Não havia clock derivado para a saída do PLL nem atraso de
entrada ou saída em qualquer pino de dado, endereço ou comando da SDRAM.

A folga de 5,49 ns que o projeto reportava cobria exclusivamente a lógica interna.
O caminho entre o FPGA e o chip de memória nunca foi analisado, e o posicionador
roteava esses pinos sem nenhuma meta temporal.

---

## 3. Hipóteses

### 3.1 Regeneração do PLL pelo Quartus — descartada

A primeira suspeita recaiu sobre o PLL. O Quartus havia sido atualizado da versão
18.1 para a 25.1 e regenerou os arquivos do componente, e havia memória de ter
autorizado essa regeneração.

A comparação com a versão anterior mostrou parâmetros idênticos: mesma defasagem,
mesmo divisor, mesmo modo de operação. As diferenças eram a renomeação de sinais
internos e a troca de cadeias de texto de versão. A hipótese não se sustentou.

Ficou registrada, porém, uma divergência: a mensagem do commit que introduziu o
PLL mencionava defasagem de −3 ns, enquanto o código sempre teve −2 ns.

### 3.2 Margem de captura nas linhas de dados — parcialmente correta

Os primeiros dados apontavam para erros concentrados na metade inferior do
barramento, com a metade superior sempre íntegra. Como os dois chips de memória
ocupam lados opostos do encapsulamento e o arquivo de restrições não impunha nada
a eles, a hipótese de margem de captura era plausível.

Ela se revelou **correta para o defeito residual, e incorreta para o defeito
principal**. A concentração aparente na metade inferior era artefato do teste: os
dezesseis bits superiores dos valores usados eram constantes, de modo que uma
leitura do endereço errado continuava coincidindo ali.

### 3.3 Erro de endereçamento contra corrupção de dado — indistinguíveis

A hipótese de que palavras vizinhas estavam trocadas concorria com a de que um bit
de dado estava corrompido. O teste não conseguia separá-las, porque os valores
gravados eram o índice somado a uma marca, e assim palavras vizinhas diferiam em
um único bit. As duas hipóteses produziam exatamente a mesma evidência.

A separação exigiu trocar o valor gravado para o índice multiplicado por uma
constante ímpar, fazendo palavras vizinhas diferirem em vários bits. Com isso, um
valor lido ou é múltiplo válido da constante — e veio de outro endereço — ou não
é, e foi corrompido no caminho de dados.

### 3.4 A análise de timing como critério suficiente — refutada

Com o arquivo de restrições completo, uma varredura da defasagem do PLL indicou o
valor zero como ótimo, com folga positiva e ampla em ambos os caminhos.

Em hardware, essa configuração deslocou todos os acessos em exatamente uma
palavra, em cem por cento dos casos. O mapa de erros por bit assumiu a sequência
1024, 512, 256, 128, 64, 32, 16, 8 — assinatura inequívoca da soma de quatro bytes
com propagação de vai-um.

A razão: com defasagem zero, o chip amostra na mesma borda em que o FPGA altera o
barramento. O analisador resolve essa coincidência escolhendo a borda de captura
seguinte, o que produz uma janela de vinte nanossegundos e folga aparente
generosa — mas essa não é a relação que a máquina de estados do controlador
implementa.

---

## 4. Soluções

### 4.1 Registro do endereço na requisição Wishbone

O processo que captura a requisição registrava o dado de escrita, a seleção de
bytes e o sinal de escrita no instante em que a transação era aceita. O endereço
não: derivava do barramento por atribuição concorrente, acompanhando-o de forma
combinacional durante toda a execução da máquina de estados.

Como essa máquina consome vários ciclos entre o comando de ativação de linha e o
comando de leitura ou escrita, qualquer movimento do barramento nesse intervalo
fazia um comando capturar a linha de um endereço e o outro capturar a coluna de
outro.

A correção foi registrar o endereço junto com o restante da requisição.

**Por que a simulação não encontrou.** A testbench mantém o endereço estável
durante toda a transação — comportamento natural de uma testbench escrita à mão. O
mestre real não mantém. O defeito residia precisamente na interface com o mestre
real, fora do que o modelo idealizado exercitava.

### 4.2 Conexão efetiva do PLL ao clock da memória

A inspeção do nível superior revelou que a saída do PLL estava desconectada e que
o clock entregue à memória continuava vindo de um inversor combinacional, sob o
comentário "diagnóstico temporário". O PLL existia apenas para fornecer o sinal de
travamento usado no reset.

Ou seja, a defasagem configurada nunca esteve em vigor, e o clock do chip saía de
lógica combinacional roteada genericamente até o pino — exatamente a condição que
a introdução do PLL pretendia eliminar.

A correção conectou a saída do PLL ao pino, com defasagem de 180 graus. Esse é o
valor que a máquina de estados pressupõe: ela altera endereço e comando na borda
do clock de sistema e espera que o chip amostre meio ciclo depois.

### 4.3 Restrições de timing para a interface de memória

O arquivo de restrições passou a declarar um clock derivado para o pino de clock
da memória e atrasos de entrada e saída para os pinos de dado, endereço, comando e
máscara, a partir dos parâmetros do chip.

Com isso, a mesma compilação que antes reportava folga de 5,49 ns passou a acusar
violação de 2,88 ns no caminho de leitura. O relatório anterior oferecia uma
garantia que não cobria a interface onde estava o problema.

### 4.4 Correção da interface do acelerador

Dois defeitos independentes, ambos tornando o acelerador inútil após a primeira
operação.

O primeiro: a máquina de estados dispara na borda de subida do bit de início, não
no seu nível, enquanto o driver escrevia o valor um e nunca retornava a zero.
Assim, apenas a primeira operação após o reset produzia borda. Da segunda em
diante o array não iniciava e, como o sinal de conclusão permanecia ativo da vez
anterior, a espera terminava de imediato e o driver lia o resultado do bloco
anterior.

O segundo: o sinal de conclusão exposto ao software era o do array, que pulsa a
cada uma das oito linhas processadas, e não o da operação completa. Mesmo com o
início corrigido, o software observaria a conclusão após a primeira linha e leria
um bloco com sete linhas ainda não calculadas.

A correção introduziu sinais de ocupação e conclusão em nível de operação,
expostos no registrador de estado no lugar dos sinais do array, e fez o driver
gerar a borda exigida.

**Por que o teste isolado passava.** Ele executa uma única operação logo após o
reset. O primeiro defeito exige uma segunda operação para se manifestar, e o
segundo fica oculto quando o laço de consulta do processador é lento o bastante
para observar o estado somente após as oito linhas terminarem. Era acerto por
coincidência de temporização, não verificação.

---

## 5. Estado final

### 5.1 Integridade da memória

Bateria completa sobre quatro regiões em bancos e linhas distintos, 256 palavras
de 32 bits por padrão, incluindo o padrão de endereço como dado, que jamais havia
passado:

```
Total: 0 palavras com erro em 5120
Metade inferior do barramento: 0 erros | metade superior: 0 erros
Erros classificados como endereço: 0 | como dado: 0
Verificação imediata após escrita: 0 erros
Resultado: aprovado
```

Progressão do padrão de endereço como dado ao longo das correções:

| configuração | palavras erradas | classificados como endereço |
|---|---|---|
| inicial | 1024 | 100% |
| endereço registrado | 153 | 0 |
| PLL conectado a 180° | **0** | 0 |

### 5.2 Timing

| domínio | antes (restrições incompletas) | depois |
|---|---|---|
| lógica interna | 5,49 ns | 3,26 ns |
| interface de memória | não analisada | 2,33 ns |
| caminho de leitura | violava em 2,88 ns | atende |

A redução na folga interna é esperada e desejável: ela reflete a inserção do
registrador no caminho do endereço e o fato de o analisador passar a considerar
caminhos antes ignorados.

### 5.3 Acelerador

```
Software (processador): 33350 ciclos
Hardware (acelerador):  18533 ciclos
Resultados idênticos
```

Ganho de 1,80 vez. Os números anteriores a esta correção não medem computação:
mediam o tempo de reler resultados obsoletos.

### 5.4 Inferência

Imagem de teste com rótulo sete, comparada à referência gerada por simulação
bit-exata da aritmética do firmware:

```
obtido:   -20 -15 18 17 -12 -21 -96 87 -1 24
esperado: -20 -15 18 17 -12 -21 -96 87 -1 24
classe prevista: 7
```

Os dez logits coincidem individualmente. O sistema passou a operar também com um
segundo conjunto de dados, trocando apenas os pesos e os parâmetros de
quantização — o que evidencia que o acelerador é genérico, e não ajustado a um
problema específico.

### 5.5 Questões em aberto

**Falhas transitórias de reconhecimento no barramento.** A inferência completa
acumula cerca de catorze mil e setecentas falhas de acesso, todas recuperadas por
um tratador que reexecuta a instrução. Os dados resultantes estão corretos, mas
isso reflete o mecanismo de recuperação em operação, não a ausência da falha. Cada
recuperação consome ciclos que entram nas medições de desempenho por camada.

**Travamento na formatação de uma linha de saída.** A impressão do fator de ganho
interrompia a execução de forma reprodutível, antes da mensagem final. Foi
contornada substituindo uma divisão de 64 bits pela impressão dos dois
contadores. O mecanismo não foi identificado: os argumentos de uma chamada são
avaliados antes dela, de modo que a divisão já havia concluído quando a saída
cessou no meio de um texto literal.

**Reinicializações espontâneas.** A placa reiniciou por conta própria em pelo menos
duas ocasiões, após entrar no laço de espera. A causa não foi investigada.
Hipóteses plausíveis incluem ruído no pino de reinicialização e queda de tensão ao
energizar o display.

**Parâmetros do chip de memória.** Os tempos usados nas restrições foram obtidos de
memória e estão marcados no arquivo como pendentes de conferência na folha de
dados. Não afetam o funcionamento atual, já que a defasagem foi validada em
hardware, mas afetam a confiabilidade do relatório de timing em recompilações
futuras.

---

## 6. Síntese metodológica

Os quatro defeitos corrigidos distribuem-se em categorias distintas quanto ao
método capaz de detectá-los.

**A simulação não podia encontrar o defeito principal.** Ele residia na interação
com o mestre real do barramento, e a testbench modelava um mestre idealizado que
mantinha o endereço estável. Nenhum aumento de cobertura da testbench existente o
encontraria; seria necessário modelar o mestre real ou verificar o sistema
integrado.

**A análise de timing produziu uma resposta incorreta.** Tornou o problema visível
e quantificável — o que o conjunto de restrições anterior impedia —, mas o valor
escolhido teve de ser validado em hardware. A relação entre bordas que o analisador
assumiu não correspondia à implementada pela máquina de estados.

**Testes binários custam mais do que aparentam.** Cada teste que respondia apenas
"aprovado" ou "reprovado" consumiu horas. Os que informavam *como* falhava
resolveram em minutos. A diferença entre o teste de dezesseis bytes e a bateria que
o substituiu não está na cobertura, e sim na capacidade de localizar.

**O projeto do próprio teste pode ocultar o defeito.** Padrões uniformes de memória
são cegos a erros de endereçamento. Valores de teste cujos vizinhos diferem em um
único bit tornam indistinguíveis duas causas distintas. Ambos os casos ocorreram
neste ciclo, e o segundo levou a defender interpretações opostas sobre a mesma
evidência antes que a limitação fosse percebida.
