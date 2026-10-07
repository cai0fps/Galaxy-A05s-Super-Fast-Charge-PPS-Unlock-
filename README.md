# Galaxy A05s Super Fast Charge (PPS) Unlock

## 00. ÍNDICE / STATUS

**VERSÃO ATUAL**
v2.0-native-patcher

**PATCH ATIVO**
`usbpd_pd_contact`: `CMP W4,#2000` → `CMP W4,#0`

**PATCH DESATIVADO**
`usbpd_get_pps_status_max`

**OBJETIVO DO TESTE ATUAL**
Permitir APDO 3300–11000 mV / 1800 mA sem falsificar corrente, tensão ou RDO.

**NÃO COMPROVADO AINDA**
25 W / 2250 mA / desbloqueio universal de PPS.

### Tabela de Progresso

| Fase | Objetivo                             | Estado          |
| ---- | ------------------------------------ | --------------- |
| 1    | Reverse engineering                  | ✅               |
| 2    | Remover filtro artificial de 2000 mA | ✅               |
| 3A   | PPS Request                          | ✅               |
| 3B   | ACCEPT / PS_RDY                      | ✅               |
| 3C   | SP2130 / FC2                         | ✅               |
| 3D   | Validar 20/25 W                      | ⏳               |
| 3E   | Mapear votes/limites                 | ⏳               |
| 4    | Determinar limites artificiais       | ⏳               |
| 5    | Native Patcher                       | ✅ preparado     |
| 5.1  | Primeiro boot real                   | 🔜              |
| 6    | Desbloqueio 25 W, se comprovado      | 🔒 não iniciado |

---

## 01. DIAGNÓSTICO INICIAL
- **01.1 Hardware:** Galaxy A05s (SM-A057M)
- **01.2 UPM6918D:** CI de Carga e controle
- **01.3 RT1711H:** Controlador TCPC (I2C Bus 2, `0x4e`)
- **01.4 SP2130:** Carga rápida
- **01.5 Stack USB-PD:** Kernel nativo (Samsung)

## 02. FASE 1 — REVERSE ENGINEERING
Mapeamento dos componentes vitais:
- `pd_policy_manager`
- `tcpc_class`
- `tcpc_rt1711h`
- `aw35615`
- Fluxo de negociação

## 03. FASE 2 — QUALIFICAÇÃO PPS
- **APDO #4 / APDO #5:** Identificação dos APDOs enviados pela fonte.
- **Filtro 2000 mA:** Descoberta do threshold mínimo OEM.
- **Patch 1800 mA:** Adaptação lógica do threshold.
- **Resultado:** Qualificação desbloqueada.

## 04. FASE 3 — PPS REAL
- **3A — REQUEST:** O aparelho envia requisição PPS genuína.
- **3B — ACCEPT / PS_RDY:** O carregador aceita e libera VBUS.
- **3C — SP2130 / FC2:** Handover para o circuito de alta potência.
- **3D — 20 W / 25 W:** *(Em validação)*
- **3E — VOTES / LIMITES:** *(Em mapeamento)*

## 05. FASE 4 — LIMITES ARTIFICIAIS
Auditoria de correntes, tensões, regras térmicas (*thermal*) e de power path. *(Pendente)*

## 06. FASE 5 — NATIVE PATCHER
- **6.1 Kprobe → Native:** Pivot completo abandonando Kprobe.
- **6.2 assinatura ARM64:** `e41740b99f401f71.[bB]....54`
- **6.3 `usbpd_pd_contact`:** Substituição `cmp w4, #2000` por `cmp w4, #0`.
- **6.4 `usbpd_get_pps_status_max`:** Identificado, porém desativado.
- **6.5 validação:** Regras estritas de ocorrência e binário.
- **6.6 KernelSU / Magic Mount:** Substituição indetectável via bind-mount.
- **6.7 teste físico:** *(Aguardando log do primeiro boot)*

## 07. FASE 6 — 25 W / PPS
(Bloqueado: Requer dados da Fase 5)
- Fonte 20 W / 25 W
- APDOs anunciados vs RDO
- VBUS / IBUS
- Potência real

## 08. SEGURANÇA
- OVP / OCP
- Thermal / JEITA
- SP2130 protection
- Rollback do Patcher

## 09. MÓDULO
- `module.prop`
- `customize.sh` (Motor do Patcher)
- `action.sh`
- Build / Package (`package_v2.py`)

## 10. HISTÓRICO
- `v1.7-kprobe`: Código legado descontinuado (Proof of Concept).
- `v2.0-native-patcher`: Versão base atual.
