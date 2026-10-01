# Galaxy A05s — Super Fast Charge (USB-PD PPS Unlock)

🌐 **[English Version](README_EN.md)** | **[Versão em Português](README.md)**

> **Autor e Desenvolvedor:** [@cai0fps](https://github.com/cai0fps)  
> **Dispositivo Alvo:** Samsung Galaxy A05s (`SM-A057M` / `SM-A057F` / `SM-A057G`)  
> **Plataforma:** Qualcomm Snapdragon 680 4G (`SM6225` / `bengal`)  
> **Compatibilidade:** KernelSU / KernelSU Next / Magisk — Stock OneUI & Custom ROMs  

---

## ⚡ Visão Geral do Projeto

O **Samsung Galaxy A05s** possui hardware nativo de alta potência com topologia de **Charge Pump de divisão 2:1 (Silergy SP2130)** acoplado ao controlador USB Type-C PD PHY (**Richtek RT1711H**). Teoricamente, o aparelho suporta até 25W de carregamento (Super Fast Charging / USB-PD PPS).

No entanto, no firmware original da Samsung, existe uma trava artificial no driver de política de energia (`pd_policy_manager.ko`). Ao conectar fontes USB-PD PPS de 20W ou adaptadores universais cujo APDO declare corrente nominal inferior a 2.000 mA (por exemplo, `3.3V–11.0V @ 1.8A`), o kernel rejeita silenciosamente o contrato PPS e força o recuo para o modo lento padrão de 5V (1.5A a 2.0A).

Este projeto desenvolveu uma solução universal via **Kernel Kprobes** e bypass de integridade ELF para interceptar dinamicamente a avaliação de contratos USB-PD, liberando o handshake PPS, a elevação do VBUS para ~9,0 V – 9,7 V e o chaveamento do SP2130 com regulação em malha fechada sem desativar nenhuma proteção térmica ou de hardware.

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
   * Se for menor que 2.000 mA, armazena o valor real em memória de controle (`[kp1 + 0x80]`) e eleva temporariamente `regs->regs[4]` para 2.000 para passar na comparação OEM sem falhas.
2. **Pre-Handler 2 (`+0x2b0`)**:
   * Intercepta a montagem do Request.
   * Restaura o valor real anunciado em `regs->regs[3]`.
   * O pacote RDO transmitido reflete com precisão exata a especificação da fonte conectada, sem provocar sobrecorrente no primário.

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

## 🌡️ Mapeamento Térmico e Algoritmo de Arrefecimento

Descobrimos no arquivo de configuração do daemon térmico da Qualcomm (`/vendor/etc/thermal-engine.conf`) a regra de atenuação de corrente da bateria:

```text
[BATT_SKIN_MITIGATION]
algo_type monitor
sensor quiet-therm
thresholds     38000  39000  40000  41000  43000
thresholds_clr 36000  38000  39000  40000  41000
actions        battery battery battery battery battery
action_info    5      6      7      8      9
```

* **Sensor de Carcaça (`quiet-therm`)**: Se o sensor ultrapassa **43 °C** (comum quando a tela de 90Hz e os núcleos da CPU estão ativos), o daemon sobe o nível térmico para **9**, forçando o FC2 a suspender o Charge Pump (`cp enable: 0`).
* **Solução Inteligente do Módulo**: Quando o carregador é plugado e a tela apaga, o daemon do módulo arrefece a CPU Big Cluster. O sensor `quiet-therm` cai para $< 38\text{ °C}$, o nível térmico zera (`cdev26 = 0`) e o **Charge Pump opera no talo a ~2,8 A contínuos**.

---

## 🎮 Instalação e Funcionalidades

O módulo foi empacotado no padrão oficial para **KernelSU**, **KernelSU Next** e **Magisk**:

### 1. Novo Instalador com Cursor Interativo via Teclas de Volume
Ao instalar o arquivo `.zip` no gerenciador root, um menu dinâmico com cursor interativo é exibido no console do instalador:
* **`[VOL -]` = Navegar / Mudar Opção**: Move o cursor ciclicamente entre as opções (`1 -> 2 -> 3 -> 1...`).
* **`[VOL +]` = CONFIRMAR**: Confirma a opção atualmente selecionada pelo cursor.
* **Timeout de Segurança (30s)**: Caso não haja interação, seleciona automaticamente o Modo 3 (ULTRA).

#### Perfis Disponíveis:
* **`[>] 1. Modo Normal`**: Handshake PPS 25W direto até 100% de carga, mantendo os clocks de CPU em estado de fábrica.
* **`[>] 2. Modo Inteligente`**: Potência de 25W até 100% com Arrefecimento Dinâmico de CPU durante tela apagada, garantindo carcaça fria.
* **`[>] 3. Modo ULTRA (Recomendado / Máxima Potência)`**: 
  - **25W Forçado** sem restrições.
  - **Bypass Térmico Qualcomm**: Zera ativamente a atenuação do `thermal-engine` (`cooling_device26` e `27`), impedindo o corte para 10W.
  - **Bypass de Tela Acesa (SIOP)**: Mantém corrente em 3.300 mA e `siop_level = 100` mesmo com a tela ligada.
  - **Arrefecimento Ultra em Standby**: Clocks reduzidos para 902 MHz (Silver) e 825 MHz (Gold) com tela apagada para resfriamento rápido do chassi.

*(Nota: Todas as travas e modos vitrine de 300mA e limites de 80%/85% foram permanentemente removidos. A carga opera com potência máxima até 100%).*

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
Para usuários do KernelSU Next com suporte a WebUI, o módulo inclui interface gráfica com monitor de potência em tempo real (Watts, Volts, Amperes), bridge Java assíncrona corrigida e alternador de perfil com 1 clique (Normal, Inteligente e ULTRA).

---

## 📁 Estrutura de Arquivos

```
Galaxy_A05s_SuperFastCharge_v3.5.zip
├── module.prop                  # Metadados e versão do módulo v3.5
├── customize.sh                 # Novo menu com cursor interativo via botões de volume
├── service.sh                   # Daemon de boot, bypass térmico/tela e arrefecimento
├── action.sh                    # Script do botão "Ação" do KernelSU
├── config.prop                  # Perfil ativo selecionado pelo usuário
├── pps_kp_override.ko           # Driver assinado com kprobes universais
├── webroot/
│   └── index.html               # Dashboard WebUI para KernelSU Next (Bridge corrigida)
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
