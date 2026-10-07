# Galaxy A05s Super Fast Charge (PPS) Unlock v2.0

> **ATENÇÃO:** O Antigravity e o projeto passaram por uma reestruturação COMPLETA (Fase 5). 
> Abandone as versões antigas baseadas no Kprobe. O Kprobe (Phase 1-3) injetava valores hardcoded de 2000mA de forma insegura, corrompendo o RDO e impedindo a negociação correta com o carregador original.

## O Problema Original
O `pd_policy_manager` original da Samsung para o A05s exige que o carregador conectado forneça **mínimo de 2000mA** de corrente para liberar o perfil PPS. 
No entanto, fontes originais de 20W e algumas de 25W anunciam `1800mA` ou `1670mA` em altas tensões (ex: 11.0V/1.8A = 19.8W).
Como `1800mA < 2000mA`, a função OEM `usbpd_pd_contact` rejeita o APDO e te joga de volta para carregamento lento.

## Como o Patcher Nativo Hexadecimal v2.0 resolve isso?
Ao invés de tentar enganar a função via injeção em memória (`kprobe`), nós modificamos estruturalmente o próprio arquivo ELF `pd_policy_manager.ko` do seu firmware atual usando um **Magic Mount do KernelSU/Magisk**.

Durante a instalação (`customize.sh`), o script:
1. Copia o `.ko` original do seu firmware.
2. Faz um _dump_ hexadecimal e valida se ele é um ELF AArch64 compatível.
3. Procura a **assinatura exata (24 bytes)** do check em `usbpd_pd_contact`:
   ```asm
   ldr  w4, [sp, #0x14]  ; Carrega a corrente do Source Capability
   cmp  w4, #0x7d0       ; Compara com 2000mA
   b.lt <rejeita>        ; Salta e rejeita se for menor
   ```
4. Aplica um `hexpatch` pontual trocando a comparação para:
   ```asm
   cmp  w4, #0
   ```
5. Valida a modificação.
6. Instala a cópia nativamente patcheada por cima do arquivo original usando bind-mount, sem corromper nenhuma assinatura DM-Verity!

Com essa instrução alterada, qualquer APDO > 0mA é aprovado, **mas a corrente real lida do carregador (ex: 1800mA) é preservada e repassada intacta para a montagem final do RDO**. O seu carregador entregará o máximo que ele consegue (ex: 19.8W a 11V/1.8A) de forma nativa.

## Segurança
- O patcher inclui quatro níveis de verificação estrita. Se a assinatura do Kernel da Samsung não for **exatamente idêntica**, a instalação é abortada sem fazer nenhuma modificação, garantindo que o módulo nunca quebre seu celular após atualizações OTA (Over-the-Air).
- O patch 2 (`usbpd_get_pps_status_max`) vem **desativado por padrão**, sendo necessário ativá-lo no `customize.sh` apenas se novos testes provarem ser necessário.

## Instalação
1. Remova a versão antiga v1.7.
2. Instale o pacote `sfc_pps_native_v2.0.zip` via KernelSU / Magisk.
3. Reinicie.
4. Conecte o carregador original e verifique se aparece "Super Fast Charging".
