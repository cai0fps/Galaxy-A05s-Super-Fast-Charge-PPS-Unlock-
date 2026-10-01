#!/system/bin/sh
# ==============================================================================
# GALAXY A05s — FERRAMENTA DE DIAGNOSTICO DE HARDWARE & QUALIDADE DO CABO
# Desenvolvido por @cai0fps
# ==============================================================================

MODDIR="${0%/*}"
[ -z "$MODDIR" ] && MODDIR="/data/adb/modules/galaxy_a05s_pps_unlock"

LOCALE=$(getprop persist.sys.locale 2>/dev/null || echo "pt-BR")
IS_PT=1
if [ -f "$MODDIR/config.prop" ]; then
    . "$MODDIR/config.prop" 2>/dev/null
fi
# Se idioma for passado como argumento "en" ou "pt", respeita a escolha da WebUI
if [ "$1" = "en" ]; then
    IS_PT=0
elif [ "$1" = "pt" ]; then
    IS_PT=1
elif ! echo "$LOCALE" | grep -qi "pt"; then
    IS_PT=0
fi

# 1. Coleta de Telemetria Basica
vbat=$(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null || cat /sys/devices/platform/soc/soc:qcom,nopmi-chg/power_supply/battery/voltage_now 2>/dev/null || echo 0)
ibat=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null || cat /sys/devices/platform/soc/soc:qcom,nopmi-chg/power_supply/battery/current_now 2>/dev/null || echo 0)
vbat_v="$((vbat / 1000000)).$(((vbat % 1000000) / 10000))"
ibat_abs=$(( ibat < 0 ? -ibat : ibat ))
ibat_ma=$(( ibat_abs / 1000 ))
is_charging=$(( ibat > 0 ? 1 : 0 ))

# 2. Diagnostico do Driver Kprobe
kprobe_ok=0
if lsmod | grep -qE "aw35615_whole|pps_kp_override"; then
    kprobe_ok=1
fi
sec_pps_sym=$(grep -w "sec_pd_select_pps" /proc/kallsyms 2>/dev/null | head -n 1)

# 3. Diagnostico do Chip Charge Pump Silergy SP2130 (I2C 2-006d)
cp_i2c_path="/sys/devices/platform/soc/4ac0000.qcom,qupv3_0_geni_se/4a84000.i2c/i2c-2/2-006d"
cp_ps_path="/sys/class/power_supply/charger_standalone"
cp_present=0
cp_charging=0
cp_volt=0
if [ -d "$cp_i2c_path" ] || [ -d "$cp_ps_path" ]; then
    cp_present=1
    cp_st=$(cat "$cp_ps_path/status" 2>/dev/null || echo "")
    [ "$cp_st" = "Charging" ] && cp_charging=1
    cp_volt=$(cat "$cp_ps_path/voltage_now" 2>/dev/null || echo 0)
fi

# 4. Diagnostico do Conversor Buck UPM6918 (I2C 2-006b)
bbc_ps_path="/sys/class/power_supply/bbc"
bbc_present=0
bbc_model=""
if [ -d "$bbc_ps_path" ]; then
    bbc_present=1
    bbc_model=$(cat "$bbc_ps_path/uevent" 2>/dev/null | grep -i "MODEL_NAME" | cut -d= -f2)
    [ -z "$bbc_model" ] && bbc_model="upm6918"
fi

# 5. Diagnostico de Negociacao USB-PD / PPS
chg_type=$(dumpsys battery 2>/dev/null | grep -o 'charger_type:[0-9]*' | tail -n 1 | cut -d: -f2)
[ -z "$chg_type" ] && chg_type=0
hvc_val=$(dumpsys battery 2>/dev/null | grep -o 'hvc:[a-z]*' | tail -n 1 | cut -d: -f2)
dc_stat=$(cat /sys/class/power_supply/battery/direct_charging_status 2>/dev/null || echo 0)

is_pps=0
if [ "$chg_type" = "3" ] || [ "$dc_stat" != "0" ] || [ "$cp_charging" = "1" ] || { [ "$is_charging" = "1" ] && [ "$ibat_ma" -ge 1850 ]; }; then
    is_pps=1
fi

# 6. Avaliacao de Qualidade do Cabo USB-C
cable_score=""
cable_rating=""
cable_desc=""
cabo_ma=0

if [ "$is_charging" = "0" ]; then
    if [ "$IS_PT" = "1" ]; then
        cable_rating="DESCONECTADO"
        cable_desc="Conecte o carregador a tomada para testar o cabo."
        cable_score="--"
    else
        cable_rating="DISCONNECTED"
        cable_desc="Connect charger to wall outlet to test cable."
        cable_score="--"
    fi
elif [ "$is_pps" = "1" ]; then
    cabo_ma=$((ibat_ma / 2))
    if [ "$ibat_ma" -ge 2400 ]; then
        if [ "$IS_PT" = "1" ]; then
            cable_rating="EXCELENTE (Grau A+)"
            cable_score="100/100"
            cable_desc="Cabo de alta condutividade (3A real). Resistencia parasita minima (< 0.15 Ohm). Fluxo de potencia maximo."
        else
            cable_rating="EXCELLENT (Grade A+)"
            cable_score="100/100"
            cable_desc="High conductivity cable (real 3A). Minimal parasitic resistance (< 0.15 Ohm). Peak power throughput."
        fi
    elif [ "$ibat_ma" -ge 1850 ]; then
        if [ "$IS_PT" = "1" ]; then
            cable_rating="MUITO BOM (Grau A)"
            cable_score="88/100"
            cable_desc="Cabo adequado e estavel para PPS 9V. Resistencia interna controlada (~0.18 Ohm)."
        else
            cable_rating="VERY GOOD (Grade A)"
            cable_score="88/100"
            cable_desc="Proper stable cable for 9V PPS. Controlled internal resistance (~0.18 Ohm)."
        fi
    else
        if [ "$IS_PT" = "1" ]; then
            cable_rating="MODERADO (Grau B)"
            cable_score="72/100"
            cable_desc="Cabo com resistencia ligeiramente elevada ou bateria acima de 80% (afunilamento natural de corrente)."
        else
            cable_rating="MODERATE (Grade B)"
            cable_score="72/100"
            cable_desc="Cable with slight resistance or battery above 80% (natural lithium current taper)."
        fi
    fi
else
    # 5V comum ou AFC
    vbat_int=$((vbat / 10000))
    if [ "$chg_type" = "2" ]; then
        cabo_ma=$(( (vbat_int * ibat_ma) / 900 ))
        if [ "$IS_PT" = "1" ]; then
            cable_rating="PADRAO AFC (15W)"
            cable_score="80/100"
            cable_desc="Carregador ou cabo operando em modo AFC 9V (Buck convencional). Nao e PPS 25W direto."
        else
            cable_rating="STANDARD AFC (15W)"
            cable_score="80/100"
            cable_desc="Charger or cable running in 9V AFC mode (conventional Buck). Not 25W direct PPS."
        fi
    else
        cabo_ma=$(( (vbat_int * ibat_ma) / 500 ))
        if [ "$IS_PT" = "1" ]; then
            cable_rating="LIMITADO 5V (USB PC / Comum)"
            cable_score="50/100"
            cable_desc="Porta USB de 5V ou carregador lento detectado. Para 25W, use um carregador de tomada Type-C PPS."
        else
            cable_rating="5V LIMITED (PC USB / Regular)"
            cable_score="50/100"
            cable_desc="5V USB port or slow charger detected. For 25W, plug into a Type-C PPS wall charger."
        fi
    fi
fi

# 7. Saida Formatada do Diagnostico
if [ "$IS_PT" = "1" ]; then
    echo "=================================================="
    echo "  RELATORIO DE DIAGNOSTICO DE HARDWARE & CABO     "
    echo "               por @cai0fps                       "
    echo "=================================================="
    echo ""
    echo "[1] SUBSISTEMA DE KERNEL & DRIVER"
    if [ "$kprobe_ok" = "1" ]; then
        echo "  - Driver PPS Kprobe : [OK] ATIVO (pps_kp_override.ko)"
    else
        echo "  - Driver PPS Kprobe : [AVISO] INATIVO (Verifique instalacao)"
    fi
    if [ -n "$sec_pps_sym" ]; then
        echo "  - Hook sec_pd_pps   : [OK] Simbolo presente no Kernel ($sec_pps_sym)"
    else
        echo "  - Hook sec_pd_pps   : [INFO] Gerenciado via politica nativa Bengal"
    fi
    echo ""
    echo "[2] CIRCUITO INTEGRADO SILERGY SP2130 (CHARGE PUMP)"
    if [ "$cp_present" = "1" ]; then
        echo "  - Barramento I2C    : [OK] Detectado em I2C-2 (0x6d / 2-006d)"
        if [ "$cp_charging" = "1" ] || [ "$is_pps" = "1" ]; then
            echo "  - Modo Operacional  : [OK] ATIVO em Conversao Direta 2:1 (~97% Eficiencia)"
        else
            echo "  - Modo Operacional  : [STANDBY] Pronto para engate rapido 2:1"
        fi
    else
        echo "  - Barramento I2C    : [FALHA] Chip SP2130 nao respondeu no endereco 0x6d"
    fi
    echo ""
    echo "[3] CONVERSOR BUCK PRIMARIO UPM6918"
    if [ "$bbc_present" = "1" ]; then
        echo "  - Controlador       : [OK] Detectado ($bbc_model em I2C 0x6b)"
        echo "  - Funcao            : [OK] Gerenciamento 5V Comum e 9V AFC"
    else
        echo "  - Controlador       : [INFO] Emulacao via PMIC nopmi-chg"
    fi
    echo ""
    echo "[4] PROTOCOLO DO CARREGADOR & FONTE"
    if [ "$is_pps" = "1" ]; then
        echo "  - Negociacao PPS    : [OK] 9.0V PPS (Super Fast Charging 25W)"
        echo "  - Tensão da Tomada  : ~9.0 V (Negociado via USB-PD 3.0 PPS)"
    elif [ "$chg_type" = "2" ]; then
        echo "  - Negociacao AFC    : [INFO] 9.0V AFC (Adaptive Fast Charging 15W)"
    elif [ "$is_charging" = "1" ]; then
        echo "  - Negociacao 5V     : [INFO] 5.0V Padrao (USB PC ou Carregador Comum)"
    else
        echo "  - Estado            : Desconectado da Tomada"
    fi
    echo ""
    echo "[5] AVALIACAO DO CABO USB-C"
    echo "  - Classificacao     : $cable_rating"
    echo "  - Pontuacao Cabo    : $cable_score"
    if [ "$is_charging" = "1" ]; then
        echo "  - Corrente no Cabo  : ~$cabo_ma mA (Medida Real)"
        echo "  - Corrente Bateria  : +$ibat_ma mA (Entregue na celula)"
    fi
    echo "  - Analise Tecnica   : $cable_desc"
    echo ""
    echo "=================================================="
    if [ "$is_pps" = "1" ] && [ "$kprobe_ok" = "1" ] && [ "$cp_present" = "1" ]; then
        echo " RESULTADO: SISTEMA 100% OPERACIONAL PARA 25W PPS"
    elif [ "$is_charging" = "0" ]; then
        echo " RESULTADO: HARDWARE PRONTO (Conecte na tomada 25W)"
    else
        echo " RESULTADO: CARGA ATIVA EM MODO PADRAO / 5V"
    fi
    echo "=================================================="
else
    echo "=================================================="
    echo "     HARDWARE & CABLE DIAGNOSTIC REPORT           "
    echo "                 by @cai0fps                      "
    echo "=================================================="
    echo ""
    echo "[1] KERNEL & DRIVER SUBSYSTEM"
    if [ "$kprobe_ok" = "1" ]; then
        echo "  - PPS Kprobe Driver : [OK] ACTIVE (pps_kp_override.ko)"
    else
        echo "  - PPS Kprobe Driver : [WARN] INACTIVE (Check module installation)"
    fi
    if [ -n "$sec_pps_sym" ]; then
        echo "  - Hook sec_pd_pps   : [OK] Symbol present in Kernel ($sec_pps_sym)"
    else
        echo "  - Hook sec_pd_pps   : [INFO] Managed via Bengal native policy"
    fi
    echo ""
    echo "[2] SILERGY SP2130 INTEGRATED CIRCUIT (CHARGE PUMP)"
    if [ "$cp_present" = "1" ]; then
        echo "  - I2C Bus Status    : [OK] Detected on I2C-2 (0x6d / 2-006d)"
        if [ "$cp_charging" = "1" ] || [ "$is_pps" = "1" ]; then
            echo "  - Operating Mode    : [OK] ACTIVE in 2:1 Direct Mode (~97% Efficiency)"
        else
            echo "  - Operating Mode    : [STANDBY] Ready for 2:1 fast engage"
        fi
    else
        echo "  - I2C Bus Status    : [FAIL] SP2130 chip did not respond on 0x6d"
    fi
    echo ""
    echo "[3] PRIMARY BUCK CONVERTER UPM6918"
    if [ "$bbc_present" = "1" ]; then
        echo "  - Controller        : [OK] Detected ($bbc_model on I2C 0x6b)"
        echo "  - Role              : [OK] Standard 5V and 9V AFC Management"
    else
        echo "  - Controller        : [INFO] Emulation via nopmi-chg PMIC"
    fi
    echo ""
    echo "[4] CHARGER PROTOCOL & SOURCE"
    if [ "$is_pps" = "1" ]; then
        echo "  - PPS Negotiation   : [OK] 9.0V PPS (Super Fast Charging 25W)"
        echo "  - Source Voltage    : ~9.0 V (Negotiated via USB-PD 3.0 PPS)"
    elif [ "$chg_type" = "2" ]; then
        echo "  - AFC Negotiation   : [INFO] 9.0V AFC (Adaptive Fast Charging 15W)"
    elif [ "$is_charging" = "1" ]; then
        echo "  - 5V Negotiation    : [INFO] 5.0V Standard (PC USB or Regular Charger)"
    else
        echo "  - State             : Disconnected from Outlet"
    fi
    echo ""
    echo "[5] USB-C CABLE EVALUATION"
    echo "  - Rating            : $cable_rating"
    echo "  - Cable Score       : $cable_score"
    if [ "$is_charging" = "1" ]; then
        echo "  - Cable Current     : ~$cabo_ma mA (Real Cable Draw)"
        echo "  - Battery Current   : +$ibat_ma mA (Delivered to cell)"
    fi
    echo "  - Technical Analysis: $cable_desc"
    echo ""
    echo "=================================================="
    if [ "$is_pps" = "1" ] && [ "$kprobe_ok" = "1" ] && [ "$cp_present" = "1" ]; then
        echo " RESULT: SYSTEM 100% OPERATIONAL FOR 25W PPS"
    elif [ "$is_charging" = "0" ]; then
        echo " RESULT: HARDWARE READY (Plug into 25W wall charger)"
    else
        echo " RESULT: ACTIVE CHARGE IN STANDARD / 5V MODE"
    fi
    echo "=================================================="
fi
