# Publicação Científica - Análise de Qualidade

> **Análise do Potencial de Publicação do TCC**

---

## 📋 Visão Geral

Esta nota analisa o potencial de publicação do TCC sobre aceleração de redes neurais em FPGA Cyclone IV E em diferentes níveis de revistas científicas.

### 🔗 Links Relacionados
- [[Home]] - Página principal
- [[Implementation Matrix]] - Visão geral da implementação

---

## 🎯 Classificação de Revistas (QUALIS/CAPES)

### Sistema QUALIS-CAPES (Brasil)

| Estrato | Descrição | Fator de Impacto Típico |
|---------|-----------|-------------------------|
| **A1** | Excelente, top internacional | > 4.0 |
| **A2** | Muito bom, internacional | 2.0 - 4.0 |
| **A3** | Bom, internacional | 1.0 - 2.0 |
| **A4** | Bom, nacional/internacional | 0.5 - 1.0 |
| **B1** | Regular, nacional | 0.3 - 0.5 |
| **B2** | Regular, nacional | 0.1 - 0.3 |
| **B3** | Local/iniciante | < 0.1 |
| **B4/B5** | Divulgação | - |

---

## 📊 Análise do Potencial do TCC

### Pontos Fortes do Trabalho

```
┌─────────────────────────────────────────────────────────────┐
│           PONTOS FORTES                                      │
│                                                              │
│  ✅ Integração NEORV32 + Acelerador IA                      │
│     → Contribuição original na arquitetura                  │
│                                                              │
│  ✅ Matriz Sistólica 8x8 otimizada para Cyclone IV          │
│     → Design específico para hardware legado               │
│                                                              │
│  ✅ Uso de HLS/hls4ml para conversão de modelos             │
│     → Metodologia reproduzível                              │
│                                                              │
│  ✅ Throughput de até 59.52 GOPS                            │
│     → Resultados quantificáveis                             │
│                                                              │
│  ✅ Speedup de 350% vs software                             │
│     → Demonstração prática de ganhos                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Limitações do Trabalho

```
┌─────────────────────────────────────────────────────────────┐
│           LIMITAÇÕES                                         │
│                                                              │
│  ⚠️ Hardware legado (Cyclone IV - 2010)                     │
│     → Menos relevante para estado da arte                   │
│                                                              │
│  ⚠️ Precisão INT8 apenas                                    │
│     → Limitação para algumas aplicações                     │
│                                                              │
│  ⚠️ Sem comparação com GPU/TPU                              │
│     → Análise comparativa limitada                          │
│                                                              │
│  ⚠️ Rede neural simples (MNIST/CIFAR?)                      │
│     → Escala do experimento                                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 Classificação Estimada por Tipo de Veículo

### 1. Revistas Internacionais (Journals)

| Revista | Qualis | Potencial | Justificativa |
|---------|--------|-----------|---------------|
| **IEEE TCAD** | A1 | ⭐⭐ Baixo | Requer contribuição teórica forte |
| **IEEE TVLSI** | A1 | ⭐⭐ Baixo | Foco em circuits VLSI avançados |
| **IEEE FPGA** | A2 | ⭐⭐⭐ Médio | Especializada em FPGA |
| **ACM TRETS** | A2 | ⭐⭐⭐ Médio | Sistemas reconfiguráveis |
| **Microprocessors and Microsystems** | A3 | ⭐⭐⭐⭐ Alto | Hardware embarcado |
| **Integration, the VLSI Journal** | A3 | ⭐⭐⭐⭐ Alto | Design de sistemas |
| **Journal of Systems Architecture** | A4 | ⭐⭐⭐⭐⭐ Muito Alto | Sistemas embarcados |
| **IEEE Latin America** | B1 | ⭐⭐⭐⭐⭐ Muito Alto | Regional |

### 2. Conferências Internacionais

| Conferência | Qualis | Potencial | Deadline Típico |
|-------------|--------|-----------|-----------------|
| **FPGA (ACM/SIGDA)** | A1 | ⭐⭐ Baixo | Setembro |
| **FPL** | A2 | ⭐⭐⭐ Médio | Março |
| **FCCM** | A2 | ⭐⭐ Baixo | Novembro |
| **ASAP** | A3 | ⭐⭐⭐⭐ Alto | Janeiro |
| **ISCAS** | A3 | ⭐⭐⭐ Médio | Outubro |
| **SBCCI** | B1 | ⭐⭐⭐⭐⭐ Muito Alto | Abril |
| **SForum** | B2 | ⭐⭐⭐⭐⭐ Muito Alto | Maio |

### 3. Revistas Nacionais (Brasil)

| Revista | Qualis | Potencial |
|---------|--------|-----------|
| **RITA (IBPI)** | B1 | ⭐⭐⭐⭐⭐ |
| **REIC** | B2 | ⭐⭐⭐⭐⭐ |
| **Engevista** | B3 | ⭐⭐⭐⭐⭐ |
| **Revistas UFPR/UFRGS** | B2-B3 | ⭐⭐⭐⭐⭐ |

---

## 📈 Estratégia de Publicação Recomendada

### Caminho 1: Conferência Nacional → Revista Internacional

```
┌─────────────────────────────────────────────────────────────┐
│           ESTRATÉGIA GRADUAL                                 │
│                                                              │
│  Passo 1: Submeter para SBCCI (B1)                          │
│           • Obter feedback da comunidade                     │
│           • Validar resultados preliminares                  │
│           • Deadline: Abril                                  │
│                                                              │
│  Passo 2: Submeter versão estendida para revista            │
│           • Microprocessors and Microsystems (A3)            │
│           • Integration, the VLSI Journal (A3)               │
│           • Journal of Systems Architecture (A4)             │
│                                                              │
│  Tempo total: 12-18 meses                                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Caminho 2: Workshop Internacional → Conferência

```
┌─────────────────────────────────────────────────────────────┐
│           ESTRATÉGIA WORKSHOP                                │
│                                                              │
│  Passo 1: Submeter para workshop (RISC-V Summit, etc.)      │
│           • NEORV32 é tema relevante                         │
│           • Menos competitivo                                │
│                                                              │
│  Passo 2: Expandir para FPL ou ASAP                          │
│           • Adicionar experimentos                           │
│           • Comparação com outros trabalhos                  │
│                                                              │
│  Tempo total: 12-24 meses                                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔧 Melhorias para Aumentar o Potencial

### Para Alcançar A2/A1

| Melhoria | Impacto | Dificuldade |
|----------|---------|-------------|
| **Comparação com GPU** | Alto | Média |
| **Múltiplas redes (ResNet, VGG)** | Alto | Alta |
| **Análise energética detalhada** | Médio | Média |
| **FPGA moderno (Agilex)** | Alto | Alta |
| **Novo algoritmo de mapeamento** | Muito Alto | Muito Alta |

### Para Alcançar A3/A4

| Melhoria | Impacto | Dificuldade |
|----------|---------|-------------|
| **Benchmarks padronizados** | Médio | Baixa |
| **Análise de area/power** | Médio | Média |
| **Código open-source** | Médio | Baixa |
| **Documentação detalhada** | Baixo | Baixa |

---

## 📊 Estimativa Realista

### Com o Escopo Atual

```
┌─────────────────────────────────────────────────────────────┐
│           CLASSIFICAÇÃO ESTIMADA                             │
│                                                              │
│  Para TCC de Graduação:                                      │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Revista Nacional (B1-B2)     ⭐⭐⭐⭐⭐ Muito Provável │   │
│  │  Conferência Nacional (B1)    ⭐⭐⭐⭐⭐ Muito Provável │   │
│  │  Conferência Internacional    ⭐⭐⭐☆☆ Possível       │   │
│  │  Revista Internacional (A3)   ⭐⭐⭐☆☆ Possível       │   │
│  │  Revista Internacional (A2)   ⭐⭐☆☆☆ Difícil         │   │
│  │  Revista Internacional (A1)   ⭐☆☆☆☆ Muito Difícil   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  Para Dissertação de Mestrado:                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Revista Internacional (A3-A4) ⭐⭐⭐⭐☆ Provável      │   │
│  │  Conferência Internacional     ⭐⭐⭐⭐☆ Provável      │   │
│  │  Revista Internacional (A2)    ⭐⭐⭐☆☆ Possível      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 Conclusão

### Classificação Mais Provável

| Tipo de Veículo | Qualis Estimado |
|-----------------|-----------------|
| **Conferência Nacional** | **B1** (SBCCI, SForum) |
| **Revista Nacional** | **B1-B2** (RITA, REIC) |
| **Conferência Internacional** | **A3** (ASAP, ISCAS) |
| **Revista Internacional** | **A3-A4** (Microprocessors and Microsystems) |

### Recomendação Final

Para maximizar as chances de publicação:

1. **Submeta primeiro para SBCCI** (B1) - conferência brasileira de hardware
2. **Prepare versão estendida** para revista A3/A4 internacional
3. **Disponibilize código open-source** para aumentar impacto
4. **Compare com trabalhos recentes** em FPGAs similares

O trabalho tem **bom potencial para publicação em nível A3-A4** (internacional) ou **B1** (nacional), especialmente se bem executado e documentado.

---

## 📚 Referências de Classificação

- [QUALIS-CAPES](https://sucupira.capes.gov.br/sucupira/public/consultas/coleta/veiculoPublicacaoQualis/listaConsultaGeralPeriodicos.jsf)
- [Scimago Journal Rank](https://www.scimagojr.com/)
- [CORE Ranking](http://portal.core.edu.au/conf-ranks/)

---

## 🏷️ Tags

#Publication #QUALIS #ScientificPaper #Journal #Conference #Research

---

**Veja também:**
- [[Home]] - Página principal
- [[Implementation Matrix]] - Visão geral da implementação
- [[Referências]] - Bibliografia
