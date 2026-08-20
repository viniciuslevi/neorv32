# Diagramas Mermaid — RNAs, CNN e Inferência (TCC)

Diagramas prontos para exportar como imagem (Mermaid Live Editor, VS Code, ou extensões LaTeX/Markdown).

---

## Figura 1 — Modelo de Deep Learning (composição em camadas)

```mermaid
flowchart LR
    subgraph entrada["Dados brutos"]
        X["Entrada x"]
    end

    subgraph camadas["Camadas ocultas (funções compostas)"]
        L1["Camada 1<br/>f₁(x)"]
        L2["Camada 2<br/>f₂(·)"]
        L3["Camada 3<br/>f₃(·)"]
        LN["Camada N<br/>fₙ(·)"]
    end

    subgraph saida["Saída"]
        Y["Predição ŷ<br/>características de alto nível"]
    end

    X --> L1 --> L2 --> L3 --> LN --> Y

    style entrada fill:#e8f4fc,stroke:#2980b9
    style camadas fill:#fef9e7,stroke:#f39c12
    style saida fill:#eafaf1,stroke:#27ae60
```

---

## Figura 2 — Neurônio artificial (soma ponderada + função de ativação)

```mermaid
flowchart LR
    subgraph entradas["Ativações de entrada"]
        x1["x₁"]
        x2["x₂"]
        x3["x₃"]
        xn["xₙ"]
    end

    subgraph pesos["Pesos sinápticos"]
        w1["w₁"]
        w2["w₂"]
        w3["w₃"]
        wn["wₙ"]
    end

    subgraph mac["Soma ponderada (Σ MACs)"]
        SUM["Σ (xᵢ · wᵢ) + b"]
    end

    subgraph ativacao["Função não-linear"]
        ACT["σ(·)<br/>ReLU, Sigmoid, Tanh..."]
    end

    y["Saída y"]

    x1 --> w1 --> SUM
    x2 --> w2 --> SUM
    x3 --> w3 --> SUM
    xn --> wn --> SUM
    b["Bias b"] --> SUM
    SUM --> ACT --> y

    style mac fill:#fdebd0,stroke:#e67e22
    style ativacao fill:#ebdef0,stroke:#8e44ad
```

---

## Figura 3 — Operação MAC (Multiply-and-Accumulate)

```mermaid
flowchart TB
    subgraph mac_unit["Unidade MAC — base de CNN e camadas FC"]
        direction TB
        M1["MAC₁: p₁ = x₁ × w₁"]
        M2["MAC₂: p₂ = x₂ × w₂"]
        M3["MAC₃: p₃ = x₃ × w₃"]
        MD["MACₙ: pₙ = xₙ × wₙ"]
        ACC["Acumulador<br/>acc = p₁ + p₂ + p₃ + ··· + pₙ + b"]
        OUT["Resultado z = acc"]
    end

    M1 --> ACC
    M2 --> ACC
    M3 --> ACC
    MD --> ACC
    ACC --> OUT

    style mac_unit fill:#fdf2e9,stroke:#d35400
```

**Equivalência matemática:**

```mermaid
flowchart LR
    FORM["z = Σᵢ (xᵢ · wᵢ) + b"] --> NEU["Entrada da função σ(z)"]
    NEU --> Y["y = σ(z)"]

    style FORM fill:#fff,stroke:#333
```

---

## Figura 4 — Arquitetura típica de uma CNN

```mermaid
flowchart TB
    IMG["Imagem de entrada<br/>(H × W × C)"]

    subgraph bloco1["Bloco convolucional 1"]
        C1["Convolução<br/>filtros/kernels"]
        R1["Ativação<br/>ReLU"]
        P1["Pooling<br/>max/avg"]
    end

    subgraph bloco2["Bloco convolucional 2"]
        C2["Convolução"]
        R2["ReLU"]
        P2["Pooling"]
    end

    subgraph blocoN["Blocos adicionais"]
        CN["Convolução + ReLU + Pooling<br/>···"]
    end

    FLAT["Achatar<br/>(flatten)"]

    subgraph fc["Camadas totalmente conectadas (FC)"]
        FC1["FC₁ — neurônios = Σ MACs"]
        FC2["FC₂"]
    end

    OUT["Saída<br/>classes / predição"]

    IMG --> C1 --> R1 --> P1 --> C2 --> R2 --> P2 --> CN --> FLAT --> FC1 --> FC2 --> OUT

    style bloco1 fill:#d6eaf8,stroke:#2874a6
    style bloco2 fill:#d6eaf8,stroke:#2874a6
    style fc fill:#fadbd8,stroke:#c0392b
```

---

## Figura 5 — Convolução como janela deslizante (MACs locais)

```mermaid
flowchart LR
    subgraph janela["Janela local (kernel k×k)"]
        P11["p₁₁"]
        P12["p₁₂"]
        P21["p₂₁"]
        P22["p₂₂"]
    end

    subgraph kernel["Filtro (pesos)"]
        W11["w₁₁"]
        W12["w₁₂"]
        W21["w₂₁"]
        W22["w₂₂"]
    end

    MAC["Σ (pᵢⱼ · wᵢⱼ) + b"]
    RELU["ReLU"]
    MAP["Mapa de características<br/>(feature map)"]

    P11 --> MAC
    P12 --> MAC
    P21 --> MAC
    P22 --> MAC
    W11 --> MAC
    W12 --> MAC
    W21 --> MAC
    W22 --> MAC
    MAC --> RELU --> MAP

    style janela fill:#e8f8f5,stroke:#1abc9c
    style kernel fill:#fdedec,stroke:#e74c3c
```

---

## Figura 6 — Treinamento vs. Inferência

```mermaid
flowchart TB
    subgraph treino["Fase de TREINAMENTO (aprendizado)"]
        direction TB
        T1["Dados + rótulos (labels)"]
        T2["Passagem forward"]
        T3["Cálculo da perda (loss)"]
        T4["Backpropagation"]
        T5["Atualização dos pesos w"]
        T1 --> T2 --> T3 --> T4 --> T5
        T5 -.->|"pesos ajustados"| T2
    end

    subgraph inferencia["Fase de INFERÊNCIA (predição)"]
        direction TB
        I1["Dados de entrada"]
        I2["Passagem forward<br/>pesos FIXOS"]
        I3["Predição ŷ"]
        I1 --> I2 --> I3
    end

    PESOS["Modelo treinado<br/>(matriz de pesos w*)"]
    PESOS --> inferencia

    FOCO["Escopo deste TCC"]
    FOCO --> inferencia

    style treino fill:#f5eef8,stroke:#7d3c98
    style inferencia fill:#e8f8f5,stroke:#117a65,stroke-width:3px
    style FOCO fill:#117a65,color:#fff
```

---

## Figura 7 — Inferência embarcada e custo computacional (MAC)

```mermaid
flowchart TB
    subgraph modelo["Modelo CNN/RNA treinado"]
        W["Pesos w* (fixos)"]
        ARQ["Camadas Conv + FC<br/>operações MAC intensivas"]
    end

    subgraph dispositivo["Dispositivo embarcado (foco do TCC)"]
        CPU["Processador tradicional<br/>alto custo por MAC"]
        HW["Hardware especializado<br/>acelerador MAC / matricial"]
    end

    ENTRADA["Sensor / imagem / dado bruto"] --> ARQ
    W --> ARQ
    ARQ -->|"milhões de MACs"| CPU
    ARQ -->|"otimização"| HW
    CPU --> SAIDA1["Predição (lenta / limitada)"]
    HW --> SAIDA2["Predição (eficiente)"]

    style dispositivo fill:#fef5e7,stroke:#ca6f1e
    style HW fill:#d5f5e3,stroke:#1e8449,stroke-width:2px
```

---

## Figura 8 — Visão geral do pipeline de inferência (sequência)

```mermaid
sequenceDiagram
    participant D as Dados brutos
    participant P as Pré-processamento
    participant C as Camadas Conv (MAC)
    participant F as Camadas FC (MAC)
    participant A as Ativação σ
    participant S as Saída / predição

    D->>P: normalização, redimensionamento
    P->>C: tensor de entrada
    loop Cada filtro / neurônio
        C->>C: MAC (xᵢ × wᵢ) acumulado
    end
    C->>A: mapas de características
    A->>F: ativações
    loop Cada neurônio FC
        F->>F: soma ponderada (MACs)
    end
    F->>S: logits / probabilidades
    S->>S: argmax ou threshold
```

---

## Como exportar para o TCC

1. **Mermaid Live Editor:** https://mermaid.live — cole o código e exporte PNG/SVG.
2. **VS Code / Cursor:** extensão "Markdown Preview Mermaid Support" + export PDF.
3. **LaTeX:** pacote `mermaid` ou incluir SVG exportado com `\includegraphics`.

### Sugestão de legendas (TCC)

| Figura | Legenda sugerida |
|--------|------------------|
| 1 | Composição de um modelo de deep learning em camadas ocultas sucessivas. |
| 2 | Computação clássica de um neurônio artificial: soma ponderada seguida de função de ativação não-linear. |
| 3 | Operação fundamental MAC (Multiply-and-Accumulate) na base das camadas convolucionais e totalmente conectadas. |
| 4 | Arquitetura típica de uma rede convolucional (CNN) com blocos Conv–ReLU–Pool e camadas FC. |
| 5 | Operação de convolução como produto escalar local (MAC) entre janela de entrada e kernel. |
| 6 | Fases de treinamento (backpropagation) e inferência; o projeto foca exclusivamente na inferência. |
| 7 | Desafio de inferência em dispositivos embarcados motivado pelo alto volume de operações MAC. |
| 8 | Sequência do pipeline de inferência desde dados brutos até a predição final. |
