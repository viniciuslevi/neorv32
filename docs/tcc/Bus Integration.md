# Bus Integration - Desenvolvimento do Barramento

> **Integração do Acelerador com o NEORV32**

---

## 📋 Visão Geral

Para integrar o acelerador de IA ao [[NEORV32]], existem duas rotas principais de barramento discutidas academicamente. A escolha correta é fundamental para o desempenho do sistema.

### 🔗 Links Relacionados
- [[Home]] - Página principal
- [[NEORV32]] - CPU de controle
- [[Systolic Array]] - Acelerador de IA
- [[Memory Management]] - Gestão de memória

---

## 🔄 Opção A: Custom Functions Subsystem (CFS)

### Conceito

O **CFS (Custom Functions Subsystem)** permite conectar o acelerador diretamente ao barramento interno do processador. É ideal para aceleradores de baixa latência onde a CPU precisa enviar dados e receber respostas em poucos ciclos de clock.

### Características

| Aspecto | Especificação |
|---------|---------------|
| **Latência** | Mínima (típica de 8 a 13 ciclos) |
| **Acoplamento** | Forte com o processador |
| **Interface** | Protocolo simples de leitura/escrita |
| **Mapeamento** | Memória mapeada no espaço de endereçamento |

### Arquitetura CFS

```
┌─────────────────────────────────────────────────────────────┐
│                        NEORV32                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    CPU Core                          │   │
│  └───────────────────────┬─────────────────────────────┘   │
│                          │                                   │
│  ┌───────────────────────┴───────────────────────┐         │
│  │              Barramento Interno                │         │
│  │         (Memory-Mapped I/O Space)              │         │
│  └───────────────────────┬───────────────────────┘         │
│                          │                                   │
│  ┌───────────────────────┴───────────────────────┐         │
│  │                  CFS Region                    │         │
│  │  ┌─────────────────────────────────────────┐  │         │
│  │  │        Acelerador de IA                  │  │         │
│  │  │    (Latência: 8-13 ciclos)              │  │         │
│  │  └─────────────────────────────────────────┘  │         │
│  └───────────────────────────────────────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

### Vantagens do CFS

1. **Latência mínima**: Comunicação direta com a CPU
2. **Simplicidade**: Protocolo de leitura/escrita simples
3. **Acesso rápido**: Ideal para operações frequentes
4. **Controle fino**: CPU tem controle total do acelerador

### Quando Usar CFS

- ✅ Aceleradores que requerem baixa latência
- ✅ Operações síncronas com a CPU
- ✅ Transferências de dados pequenas
- ✅ Controle e configuração do acelerador

---

## 🚌 Opção B: Wishbone / Avalon-MM

### Conceito

O NEORV32 utiliza nativamente o padrão **Wishbone**. Para a DE2-115, é comum converter essa interface para **Avalon Memory-Mapped (Avalon-MM)** usando wrappers incluídos no NEORV32.

### Arquitetura Wishbone/Avalon

```
┌─────────────────────────────────────────────────────────────┐
│                        Sistema                                │
│                                                              │
│  ┌─────────────┐      ┌──────────────┐      ┌───────────┐  │
│  │   NEORV32   │      │  Wishbone    │      │  Avalon   │  │
│  │  (Wishbone) │ ───▶ │   Wrapper    │ ───▶ │   Bus     │  │
│  └─────────────┘      └──────────────┘      └─────┬─────┘  │
│                                                    │         │
│                          ┌─────────────────────────┤         │
│                          │                         │         │
│                          ▼                         ▼         │
│                 ┌──────────────┐         ┌──────────────┐   │
│                 │  Acelerador  │         │  Controlador │   │
│                 │     IA       │         │   SDRAM      │   │
│                 └──────────────┘         └──────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Vantagens do Wishbone/Avalon

1. **Compatibilidade**: Integração com IPs da Intel via Platform Designer (Qsys)
2. **DMA independente**: Acelerador pode acessar SDRAM sem CPU
3. **Escalabilidade**: Fácil adição de novos periféricos
4. **Padrão industrial**: Bem documentado e suportado

### Quando Usar Wishbone/Avalon

- ✅ Integração com IPs da Intel
- ✅ Necessidade de DMA independente
- ✅ Sistemas com múltiplos periféricos
- ✅ Transferências de dados grandes

---

## 🚀 Desenvolvimento de Bus Master

### Conceito

O TCC pode focar no design de um **"Bus Master"** para o acelerador, permitindo que ele acesse a memória SDRAM via **DMA** de forma independente da CPU.

### Arquitetura com Bus Master

```
┌─────────────────────────────────────────────────────────────┐
│                        Sistema                                │
│                                                              │
│  ┌─────────────┐                              ┌───────────┐  │
│  │   NEORV32   │                              │  SDRAM    │  │
│  │  (CPU)      │                              │  128MB    │  │
│  └──────┬──────┘                              └─────┬─────┘  │
│         │                                           │         │
│         │ Wishbone/Avalon                           │         │
│         │                                           │         │
│  ┌──────┴──────────────────────────────────────────┴─────┐  │
│  │                    Barramento                          │  │
│  │                                                        │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │              Bus Master (DMA)                    │  │  │
│  │  │  ┌─────────────────────────────────────────┐    │  │  │
│  │  │  │           Acelerador de IA               │    │  │  │
│  │  │  │       (Acesso direto à memória)          │    │  │  │
│  │  │  └─────────────────────────────────────────┘    │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Benefícios do Bus Master

| Benefício | Descrição |
|-----------|-----------|
| **Independência** | CPU livre para outras tarefas durante processamento |
| **Eficiência** | Transferências de dados otimizadas |
| **Paralelismo** | CPU e acelerador operam simultaneamente |
| **Throughput** | Maior largura de banda efetiva |

---

## 📊 Comparação das Abordagens

| Critério | CFS | Wishbone/Avalon |
|----------|-----|-----------------|
| **Latência** | Muito baixa (8-13 ciclos) | Moderada |
| **Complexidade** | Baixa | Média |
| **Integração com IPs** | Limitada | Excelente |
| **DMA Independente** | Não | Sim |
| **Escalabilidade** | Limitada | Alta |
| **Consumo de recursos** | Menor | Maior |

---

## 🎯 Recomendação para o TCC

### Abordagem Híbrida

Para maximizar o aprendizado e a flexibilidade:

```
┌─────────────────────────────────────────────────────────────┐
│                 Arquitetura Recomendada                      │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                     NEORV32                          │   │
│  └───────────────────────────┬─────────────────────────┘   │
│                              │                               │
│          ┌───────────────────┼───────────────────┐          │
│          │                   │                   │          │
│          ▼                   ▼                   ▼          │
│  ┌───────────────┐  ┌────────────────┐  ┌──────────────┐  │
│  │  CFS Region   │  │  Wishbone/     │  │  Periféricos │  │
│  │  (Controle)   │  │  Avalon (DMA)  │  │  (VGA/LCD)   │  │
│  │               │  │                │  │              │  │
│  │ - Config      │  │ - Bus Master   │  │ - Display    │  │
│  │ - Status      │  │ - SDRAM Access │  │ - UART       │  │
│  │ - Commands    │  │ - Data Load    │  │ - GPIO       │  │
│  └───────────────┘  └────────────────┘  └──────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Justificativa

1. **CFS para controle**: Baixa latência para comandos e status
2. **Wishbone/Avalon para dados**: DMA eficiente para transferências grandes
3. **Periféricos via barramento**: Integração com IPs existentes

---

## 🔧 Implementação Prática

### Passos para Integração

1. **Configurar NEORV32**
   - Habilitar interface CFS
   - Configurar Wishbone wrapper

2. **Desenvolver Acelerador**
   - Interface CFS para controle
   - Interface Avalon para DMA

3. **Integrar via Platform Designer**
   - Adicionar IPs da Intel
   - Configurar interconexão

4. **Testar Comunicação**
   - Validar latência CFS
   - Verificar throughput DMA

---

## 📚 Referências

- [NEORV32 User Guide](https://stnolting.github.io/neorv32/ug/)
- [Wishbone Specification](https://opencores.org/howto/wishbone)
- [Intel Avalon Interface Specifications](https://www.intel.com/content/www/us/en/docs/programmable/683091/current/avalon-interface-specifications.html)

---

## 🏷️ Tags

#BusIntegration #CFS #Wishbone #Avalon #DMA #PlatformDesigner #Qsys #NEORV32

---

**Veja também:**
- [[NEORV32]] - CPU de controle
- [[Memory Management]] - Gestão de memória e buffers
- [[Implementation Matrix]] - Visão geral da implementação
