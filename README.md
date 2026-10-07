# Galaxy A05s — Super Fast Charge (USB-PD PPS Unlock)

🌐 **[English Version](README_EN.md)** | **[Versão em Português](README.md)**

> **Autor e Desenvolvedor:** [@cai0fps](https://github.com/cai0fps)  
> **Dispositivo Alvo:** Samsung Galaxy A05s (`SM-A057M` / `SM-A057F` / `SM-A057G`)  
> **Plataforma:** Qualcomm Snapdragon 680 4G (`SM6225` / `bengal`)  
> **Compatibilidade:** KernelSU / KernelSU Next / Magisk — Calibrado para Samsung Galaxy A05s OneUI (Kernel 5.15 Bengal SM6225 com pd_policy_manager compatível). ROMs com alterações de kernel requerem validação de símbolos e offsets.  

---

## ⚡ Visão Geral do Projeto

O **Samsung Galaxy A05s** possui hardware nativo de alta potência com topologia de **Charge Pump de divisão 2:1 (Silergy SP2130)** acoplado ao controlador USB Type-C PD PHY (**Richtek RT1711H**). O hardware suporta até 25W de carregamento (Super Fast Charging / USB-PD PPS) quando acoplado a fontes compatíveis com a especificação nominal de 9V @ 2,77A.

No entanto, no firmware original da Samsung, existe uma trava restritiva no driver de política de energia (`pd_policy_manager.ko`). Ao conectar fontes USB-PD PPS de 18W a 20W ou adaptadores universais cujo APDO declare corrente nominal inferior a 2.000 mA (por exemplo, `3.3V–11.0V @ 1.8A`), o kernel rejeita o contrato PPS e força o recuo para o modo lento padrão de 5V (1.5A a 2.0A).

Este projeto desenvolveu uma solução via **Kernel Kprobes** para interceptar dinamicamente a avaliação de contratos USB-PD, liberando o handshake PPS, a elevação do VBUS para ~9,0 V e o chaveamento do SP2130 com regulação em malha fechada. Nos modos padrão e inteligente, as proteções térmicas de fábrica e a curva de absorção CC/CV são estritamente preservadas.

---

## 🔬 Topologia de Hardware

```
USB-C Connector
       │
       ▼
Richtek RT1711H (TCPC / PD PHY)
       │  (Comunicação BMC / CC Lines)
       ▼
Qualcomm Bengal SoC / Linux Kernel 5.15
  ├─ tcpc_class.ko
  ├─ rt_pd_manager.ko
  └─ pd_policy_manager.ko ──► [KPROBE HOOK @cai0fps]
       │
       ├──────────────────────────────────────────────┐
       ▼ (Modo PPS / Alta Potência 2:1)               ▼ (Modo Trickle / CV)
Silergy SP2130 (Charge Pump 2:1)             UPM6918 (Buck Charger)
  η ≈ 97% | Chaveamento a capacitor            Regulação de saturação
       │                                              │
       └──────────────────────┬───────────────────────┘
                              ▼
                   SM5602 Fuel Gauge (BMS)
                              ▼
                 Bateria Li-ion (5.000 mAh)
```

---

## 🧠 A Engenharia Reversa da Trava OEM

Descompilando a função `usbpd_pd_contact` dentro de `pd_policy_manager.ko`, foi isolada a instrução de rejeição em assembly ARM64:

```arm64
// usbpd_pd_contact (pd_policy_manager.ko)
+0x1f8:  mov    w20, #-1             // Inicializa estado do APDO = não encontrado
+0x1fc:  mov    w24, #0x2710         // Teto de tensão = 10.000 mV (10V)
...
+0x250:  cmp    w4, #0x7d0           // <--- A TRAVA OEM: w4 < 2000 mA?
+0x254:  b.lt   +0x280               // Se menor que 2.000 mA, DESCARTA O APDO!
...
+0x2a8:  mov    w2, #0x2328          // Tensão padrão = 9000 mV
+0x2ac:  mov    w3, #0x7d0           // Corrente requisitada padrão = 2000 mA
+0x2b0:  mov    w20, #1              // Marca APDO como qualificado
+0x2b8:  bl     usbpd_pps_enable_charging
```

### O Funcionamento do Hook Dinâmico (`pps_kp_override.ko`):
1. **Pre-Handler 1 (`+0x250`)**:
   * Lê a corrente anunciada pelo carregador diretamente em `regs->regs[4]`.
   * Se for menor que 2.000 mA, armazena o valor real anunciado da fonte e eleva temporariamente `regs->regs[4]` para 2.000 para passar na comparação OEM sem descartar o APDO.
2. **Pre-Handler 2 (`+0x2b0`)**:
   * Intercepta a montagem do Request (RDO).
   * Restaura o valor real anunciado em `regs->regs[3]`.
   * O pacote RDO transmitido reflete a especificação suportada pela fonte, evitando requisição indevida de sobrecorrente.

> [!WARNING]
> **Sensibilidade de Offsets e ABI:** Os offsets `+0x250` e `+0x2b0` dependem do binário exato do driver compilado pela Samsung. Atualizações de segurança mensais ou kernels customizados com diferentes opções de compilação podem alterar os endereços das instruções. Se o kernel divergir, os kprobes podem atingir instruções incorretas.

---

## 📊 Decodificação de Protocolo: RDO Bruto Transmitido

Durante a validação prática com carregador de 20W (APDO `3300–11000 mV @ 1800 mA`), capturamos o pacote de requisição bruto transmitido pelo chip TCPC:

```text
< 2423.777>TCPC-PE:NewReq, rdo:0x53038424
[ 2423.805585] rt-pd-manager: pd_tcp_notifier_call sink vbus 9000mV 1800mA
< 2438.119>TCPC-PE-EVT:accept
< 2438.141>TCPC-PE-EVT:ps_rdy
```

### Decomposição Bit a Bit do RDO `0x53038424` (USB-PD 3.0 Spec, Tab. 6-15):

| Campo | Bits | Hex / Bruto | Valor Físico |
|---|---|---|---|
| **Object Position** | [31..28] | `0x5` | **APDO #5 selecionado** |
| **GiveBack Flag** | [27] | `0` | Não devolve potência |
| **Capability Mismatch** | [26] | `0` | Requisitos do dispositivo atendidos |
| **USB Comm Capable** | [25] | `1` | Suporte a dados USB ativo |
| **No USB Suspend** | [24] | `1` | Carregamento ativo em repouso |
| **Output Voltage** | [19..9] | `450` (`0x1C2`) | $450 \times 20\text{ mV} = \mathbf{9.000\text{ mV}}$ |
| **Operating Current** | [6..0] | `36` (`0x24`) | $36 \times 50\text{ mA} = \mathbf{1.800\text{ mA}}$ |

---

## ⚡ Entenda a Física do Carregamento: VBUS vs VBAT

Compreender o circuito evita interpretações equivocadas sobre as leituras de potência:

### 1. Tensão do Barramento ($V_{bus}$) vs Tensão da Bateria ($V_{bat}$)
* **Tensão do Barramento (Cabo USB-C)**: No protocolo PPS, a fonte injeta entre **~9.0 V e 9.7 V** no cabo USB. Essa tensão elevada permite transmitir energia com menor corrente no condutor, reduzindo aquecimento resistivo ($P_{\text{perda}} = R \times I^2$).
* **Tensão da Célula de Lítio (1S)**: A bateria opera entre **~3.4 V (0%)** e **~4.40 V (100%)**. Nenhuma tensão acima desse limite pode incidir diretamente na célula química.

### 2. Conversão 2:1 pelo Charge Pump (Silergy SP2130)
O chip **SP2130** atua como conversor comutado a capacitores com rendimento de $\approx 97\%$:
* **Tensão entregue à bateria**: $V_{bat} \approx \frac{V_{bus}}{2}$ (ex.: $\frac{9.0\text{ V}}{2} \approx 4.5\text{ V}$ antes da saturação)
* **Corrente multiplicada**: $I_{bat} \approx 2 \times I_{bus} \times \eta$ (ex.: $1.4\text{ A}$ no cabo resulta em $\approx 2.7\text{ A} - 2.8\text{ A}$ na bateria)

### 3. Cálculo Correto da Potência e Limites Físicos da Fonte
* **Potência de Entrada no Cabo ($P_{bus}$)**:
  $$P_{bus} = V_{bus} \times I_{bus}$$
  * Em fonte de **20W** com contrato $9.0\text{ V} \times 1.8\text{ A}$, o teto físico é **$16.2\text{ W}$** no barramento.
  * Em fonte genuína de **25W** (ex.: Samsung EP-TA800 com contrato $9.0\text{ V} \times 2.77\text{ A}$), o teto físico atinge **$25.0\text{ W}$**.
  * Se a medição em dado instante registrar $V_{bus} = 9.0\text{ V}$ e $I_{bus} = 1.4\text{ A}$, a potência fornecida é $9.0 \times 1.4 \approx \mathbf{12.6\text{ W}}$.
* **Potência Líquida Absorvida pela Célula ($P_{bat}$)**:
  $$P_{bat} = V_{bat} \times I_{bat}$$
  * Para $V_{bat} = 3.98\text{ V}$ e $I_{bat} = 2.78\text{ A}$, a potência química líquida é:
    $$3.98\text{ V} \times 2.78\text{ A} \approx \mathbf{11.06\text{ W}}$$
  > [!IMPORTANT]
  > **Nota Dimensional:** Nunca multiplique a tensão do cabo ($9\text{ V}$) pela corrente da bateria ($2.8\text{ A}$). Esse cálculo ($9\text{ V} \times 2.8\text{ A} = 25.2\text{ W}$) mistura grandezas de dois estágios isolados pelo conversor 2:1, gerando uma potência fictícia.

### 4. A Curva Química CC/CV (Por que a potência cai antes de 100%?)
O carregamento de baterias de íon de lítio divide-se em duas etapas obrigatórias:
1. **Fase CC (Corrente Constante)**: De 0% até aproximadamente 75%–80%, a corrente permanece alta enquanto a tensão sobe gradativamente.
2. **Fase CV (Tensão Constante)**: A partir de ~80%, a tensão atinge o patamar máximo (~4.35V a 4.45V). A física eletroquímica exige que a corrente caia progressivamente para estabilizar o potencial elétrico e prevenir danos moleculares aos eletrodos, finalizando próximo a 0 A em 100%. **Nenhum dispositivo seguro opera em potência máxima até 100%.**

---

## 🌡️ Mapeamento Térmico e Algoritmo de Arrefecimento

No daemon térmico da Qualcomm (`/vendor/etc/thermal-engine.conf`), encontramos regras de mitigação para proteger o chassi:

```text
[BATT_SKIN_MITIGATION]
algo_type monitor
sensor quiet-therm
thresholds     38000  39000  40000  41000  43000
thresholds_clr 36000  38000  39000  40000  41000
actions        battery battery battery battery battery
action_info    5      6      7      8      9
```

* **Sensor de Carcaça (`quiet-therm`)**: Se o sensor ultrapassa **43 °C** (comum com tela acesa e alta carga de CPU), o daemon aciona mitigação que reduz a corrente de carga.
* **Arrefecimento Inteligente**: Ao apagar a tela, o daemon do módulo reduz o consumo dos núcleos de alta performance da CPU. Com menor dissipação combinada, o chassi mantém-se em patamares seguros sem engatilhar throttling precoce do charge pump.

---

## 🎮 Instalação e Funcionalidades

O módulo foi empacotado para **KernelSU**, **KernelSU Next** e **Magisk**:

### 1. Instalador Interativo via Teclas de Volume
Ao instalar o arquivo `.zip`, o console exibe um menu de opções:
* **`[VOL -]` = Navegar**: Alterna entre os perfis (`1 -> 2 -> 3 -> 1...`).
* **`[VOL +]` = CONFIRMAR**: Seleciona a opção destacada.
* **Timeout Seguro (30s)**: Sem interação, seleciona automaticamente o **Modo 1 (Normal / Seguro)**.

#### Perfis de Operação:
* **`[>] 1. Modo Normal (Recomendado - Padrão Seguro)`**:
  - Habilita o handshake PPS para contratos abaixo de 2.000 mA.
  - Mantém 100% intactas todas as políticas térmicas nativas e a curva de recarga natural da Samsung.
* **`[>] 2. Modo Inteligente`**:
  - Habilita o handshake PPS com otimização dinâmica de frequências de CPU em standby para manter a temperatura do chassi reduzida.
  - Proteções térmicas e curva CV preservadas.
* **`[>] 3. Modo ULTRA (Experimental / Testes de Bancada)`**:
  - Relaxa temporariamente pontos de mitigação térmica se a bateria estiver em temperatura segura ($< 42^\circ\text{C}$).
  - Possui salvaguarda estrita: caso a bateria atinja $42^\circ\text{C}$, todas as proteções térmicas do kernel retomam a regulação normal imediatamente.

### 2. Painel Nativo no App do KernelSU (`action.sh`)
Na aba de módulos do KernelSU, toque no botão **"Ação" / "Executar"** para abrir o modal com telemetria instantânea:
```text
==================================================
    GALAXY A05s — PAINEL DE TELEMETRIA PPS
               por @cai0fps                      
==================================================

 [+] Driver Kernel   : ATIVO (Kprobe Universal @cai0fps)
 [+] Protocolo USB   : SUPER FAST CHARGING (PPS 25W ATIVO)
 [+] Charge Pump     : LIGADO (SP2130 modo 2:1 ativo)
 [+] Nivel Bateria   : 68% (Alvo: 100%)
 [+] Tensao Bateria  : 3.98 V
 [+] Corrente Real   : +2780 mA
 [+] Temp. Bateria   : 36.0 C
 [+] Temp. Carcaca   : 38.2 C (quiet-therm)
 [+] Perfil Ativo    : ULTRA (Modo 3)
 [+] Bypass Termico  : ATIVO (cur_state=0)
 [+] Bypass de Tela  : ATIVO (siop=100 / 3.3A)

==================================================
```

### 3. WebUI Integrada (`webroot/`)
Para usuários do KernelSU Next com suporte a WebUI, o módulo inclui interface gráfica com monitor de potência em tempo real (Watts, Volts, Amperes), bridge Java assíncrona corrigida, alternador de perfil com 1 clique (Normal, Inteligente e ULTRA) e o novo botão **"Executar Diagnóstico do Sistema"** com análise de condutividade do cabo USB-C.

### 4. Notificações Nativas do Sistema
O daemon em segundo plano monitora em tempo real a negociação USB-PD e emite um alerta nativo no Android assim que o protocolo PPS 9V e o Charge Pump SP2130 são engatados na tomada.

---

## 📁 Estrutura de Arquivos

```
Galaxy_A05s_SuperFastCharge_v1.6.zip
├── module.prop                  # Metadados e versão do módulo v1.6
├── customize.sh                 # Novo menu com cursor interativo via botões de volume
├── service.sh                   # Daemon de boot, bypass térmico/tela, arrefecimento e notificações
├── action.sh                    # Script do botão "Ação" do KernelSU com telemetria
├── diag.sh                      # Ferramenta de diagnóstico de hardware e qualidade do cabo
├── config.prop                  # Perfil ativo selecionado pelo usuário
├── pps_kp_override.ko           # Driver assinado com kprobes universais
├── webroot/
│   └── index.html               # Dashboard WebUI para KernelSU Next (Diagnóstico + Watts)
└── META-INF/
    └── com/google/android/
        ├── update-binary        # Entrypoint do instalador
        └── updater-script       # Script de instrução Magisk/KernelSU
```

---

## ⚠️ Termo de Responsabilidade, Isenção Legal e Consentimento de Uso

> ### 🛑 AVISO IMPORTANTE: LEIA ATENTAMENTE ANTES DE INSTALAR OU UTILIZAR
> Este projeto consiste em uma prova de conceito (PoC) de engenharia reversa e modificação de subsistemas de baixo nível do kernel Linux Android (Qualcomm Snapdragon 680). 

### 1. Natureza Experimental e Acadêmica
* Todo o código, binários, scripts e drivers disponibilizados neste repositório são fornecidos exclusivamente para **fins educacionais, de pesquisa técnica e validação experimental de protocolos de recarga (USB-PD PPS)**.
* Este software é distribuído **"COMO ESTÁ" ("AS IS")**, sem qualquer tipo de garantia expressa ou implícita, incluindo, mas não se limitando a, garantias de funcionamento ininterrupto, adequação a um propósito específico ou preservação da vida útil do equipamento.

### 2. Isenção Total de Responsabilidade do Autor (@cai0fps)
* **O desenvolvedor e autor ([@cai0fps](https://github.com/cai0fps)) NÃO se responsabiliza, em nenhuma hipótese ou circunstância jurídica, por:**
  1. **Danos Físicos ou Materiais:** Queima, curto-circuito, sobretensão ou falha irreversível de circuitos integrados (incluindo PMIC Qualcomm, chip TCPC Richtek RT1711H, Silergy SP2130 Charge Pump, fuel gauge SM5602, tela, conector USB-C ou placa-mãe).
  2. **Danos à Bateria:** Degradação acelerada da capacidade química, redução dos ciclos de vida útil, aquecimento excessivo, inchaço ou vazamento de células de íon de lítio.
  3. **Garantia:** Perda, anulação ou recusa de garantia oficial perante o fabricante Samsung ou qualquer assistência técnica autorizada decorrente do desbloqueio de bootloader, uso de KernelSU/Magisk ou execução de scripts de modificação de kernel.
  4. **Software e Dados:** Corrupção de partições, perda de dados pessoais, travamentos, reinicializações repentinas (*bootloops*) ou instabilidades operacionais do sistema operacional OneUI/Android.

### 3. Cláusula de Consentimento Geral e Irrevogável do Usuário (Para Todo o Módulo e Todos os Modos)
* **Abrangência Universal:** O consentimento e a assunção de risco aplicam-se ao **módulo em sua totalidade, abrangendo todo e qualquer modo de operação (Modo 1: Normal, Modo 2: Inteligente e Modo 3: ULTRA)**.
* **Isenção de Custos e Reparações:** O autor ([@cai0fps](https://github.com/cai0fps)) **NÃO arca, não indeniza e não se responsabiliza sob nenhuma hipótese por quaisquer custos, reparos, prejuízos, avarias ou problemas causados** direta ou indiretamente ao aparelho ou a terceiros.
* **Consentimento Informado:** Ao baixar, clonar, instalar ou utilizar este módulo em qualquer dispositivo ou configuração, o usuário declara **ciência plena, prévia e inequívoca de todos os riscos operacionais, elétricos e térmicos**, manifestando seu **consentimento livre e irrevogável** e assumindo **100% de responsabilidade civil, técnica e financeira** por quaisquer eventos decorrentes do seu uso.
* **Modo 3 (ULTRA / Alta Potência):** Ressalta-se que o Modo ULTRA opera sem os limitadores térmicos do daemon Qualcomm (`cooling_device26/27`) e sem o limite de tela ligada da OneUI (SIOP), destinando-se a testes de bancada sob monitoramento ativo do próprio usuário.

---

## 🛡️ Cláusulas Anti-Problemas e Diretrizes de Segurança (Mitigação de Riscos)

Para garantir a máxima integridade do seu aparelho e evitar acidentes ou desgaste prematuro, siga rigorosamente as seguintes recomendações:

1. **Utilize Apenas Fontes Certificadas com PPS Genuíno:**
   * Recomenda-se o uso do carregador original Samsung de 25W (`EP-TA800`) ou adaptadores de marcas renomadas com certificação oficial USB-IF (ex: Anker, Baseus, Ugreen, Essager).
   * **NUNCA** utilize fontes genéricas, réplicas sem homologação ou carregadores sem filtragem de ruído/ripple, pois oscilações na linha VBUS podem danificar o capacitor chaveado do Charge Pump SP2130.
2. **Cabo USB-C de Qualidade (Classificação 3A Mínima):**
   * Utilize cabos íntegros com fios de alimentação de bitola compatível ($3\text{ A}$ contínuos) e integridade nas linhas de comunicação CC (Configuration Channel). Cabos danificados provocam quedas de tensão no VBUS e falhas de handshake.
3. **Dissipação de Calor e Ventilação Adequada:**
   * **NUNCA** recarregue o aparelho sobre ou debaixo de superfícies isolantes térmicas (como travesseiros, lençóis, cobertores, sofás ou mochilas fechadas).
   * Evite carregar o aparelho sob luz solar direta ou em ambientes com temperatura ambiente excessivamente alta ($> 35^\circ\text{C}$).
4. **Remoção de Capinhas Protetoras Espessas:**
   * Capas de proteção muito espessas (como capas de couro ou borracha pesada anti-impacto) retêm o calor irradiado pela carcaça traseira. Recomenda-se retirá-las durante sessões de carregamento rápido no Modo ULTRA.
5. **Recomendação para Uso Cotidiano:**
   * Para o uso diário, o perfil recomendado é o **Modo 2 (Inteligente)**, pois ele atinge os 25W completos e aciona o arrefecimento dinâmico de CPU com a tela apagada, mantendo o chassi frio e preservando as margens originais de segurança.
6. **Aferição e Monitoramento Periódico:**
   * Utilize o botão **"Ação"** no KernelSU para monitorar a temperatura da bateria (`temp_c`) e da carcaça (`quiet-therm`). Caso a bateria alcance temperaturas anômalas ($> 45^\circ\text{C}$ contínuos), desconecte o carregador e aguarde o arrefecimento natural do dispositivo.

---

## 👤 Autor

Desenvolvido e pesquisado por:  
**[@cai0fps](https://github.com/cai0fps)**

---
*Aviso: Este projeto foi desenvolvido para fins educacionais e de pesquisa de engenharia reversa no kernel Linux Android.*
