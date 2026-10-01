#!/system/bin/sh
# KernelSU Action Script - Live PPS Status Dashboard por @cai0fps

LOCALE=$(getprop persist.sys.locale 2>/dev/null || getprop ro.product.locale 2>/dev/null || echo "en")
case "$LOCALE" in
    pt*|PT*) IS_PT=1 ;;
    *) IS_PT=0 ;;
esac

if [ "$IS_PT" = "1" ]; then
    echo "=================================================="
    echo "    GALAXY A05s — PAINEL DE TELEMETRIA PPS"
    echo "               por @cai0fps                       "
    echo "=================================================="
else
    echo "=================================================="
    echo "    GALAXY A05s — PPS TELEMETRY DASHBOARD"
    echo "                by @cai0fps                       "
    echo "=================================================="
fi
echo ""

# Carregar configuracao ativa
CONFIG="/data/adb/modules/galaxy_a05s_pps_unlock/config.prop"
PROFILE="ULTRA"
if [ -f "$CONFIG" ]; then
    . "$CONFIG"
fi

# Deteccao confiavel de conexao ao carregador
ac_val=$(cat /sys/class/power_supply/ac/online 2>/dev/null || echo 0)
usb_val=$(cat /sys/class/power_supply/usb/online 2>/dev/null || echo 0)
st_val=$(cat /sys/class/power_supply/battery/status 2>/dev/null || echo "")

if [ "$ac_val" = "1" ] || [ "$usb_val" = "1" ] || [ "$st_val" = "Charging" ] || [ "$st_val" = "Full" ]; then
    is_charging=1
else
    is_charging=0
fi

# Metricas brutas do hardware
vbat=$(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null || echo 0)
ibat=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null || echo 0)
temp=$(cat /sys/class/power_supply/battery/temp 2>/dev/null || echo 0)
soc=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo 0)
cdev26=$(cat /sys/class/thermal/cooling_device26/cur_state 2>/dev/null || echo 0)
quiet_t=$(cat /sys/class/thermal/thermal_zone19/temp 2>/dev/null || echo 0)

# Calculos matematicos puros sem awk
vbat_v="$((vbat / 1000000)).$(((vbat % 1000000) / 10000))"
ibat_abs=$(( ibat < 0 ? -ibat : ibat ))
ibat_ma="$(( ibat_abs / 1000 ))"
temp_c="$((temp / 10)).$((temp % 10))"
quiet_c="$((quiet_t / 1000)).$(((quiet_t % 1000) / 100))"

# Deteccao multifatorial confiavel de Super Fast Charging PPS (9V) e Fast Charging
chg_type=$(dumpsys battery 2>/dev/null | grep -o 'charger_type:[0-9]*' | tail -n 1 | cut -d: -f2)
[ -z "$chg_type" ] && chg_type=0
hvc_val=$(dumpsys battery 2>/dev/null | grep -o 'hvc:[a-z]*' | tail -n 1 | cut -d: -f2)
is_pps=0
is_afc=0

# 1. Checagem direta de Direct Charging no driver do kernel
dc_stat=$(cat /sys/class/power_supply/battery/direct_charging_status 2>/dev/null || cat /sys/devices/platform/soc/soc:qcom,nopmi-chg/power_supply/battery/direct_charging_status 2>/dev/null || echo 0)
[ "$dc_stat" != "0" ] && is_pps=1

# 1b. Checagem no power_supply do Silergy SP2130 (charger_standalone)
cp_status_raw=$(cat /sys/class/power_supply/charger_standalone/status 2>/dev/null || echo "")
[ "$cp_status_raw" = "Charging" ] && is_pps=1

# 2. charger_type == 3 do Android (Super Fast Charging / PPS)
if [ "$chg_type" = "3" ]; then
    is_pps=1
elif [ "$chg_type" = "2" ]; then
    is_afc=1
fi

# 3. High Voltage Charging (HVC)
if [ "$hvc_val" = "true" ]; then
    if [ "$ibat_ma" -gt 1800 ] || [ "$dc_stat" != "0" ] || [ "$chg_type" = "3" ] || [ "$cp_status_raw" = "Charging" ]; then
        is_pps=1
    else
        is_afc=1
    fi
fi

# 4. Checagem de dmesg recente (negociacao sink_vbus 9000 ou charge pump habilitado)
if dmesg 2>/dev/null | tail -n 40 | grep -qE "sink_vbus 9000|cp enable: 1|type\(0x84\)"; then
    is_pps=1
fi

# 5. Checagem de hardware: no Galaxy A05s o Buck 5V e limitado a 2A.
# Qualquer corrente >= 1850mA so e fisicamente possivel no SP2130 (PPS 2:1 a 9V)!
if [ "$is_charging" = "1" ] && [ "$ibat_ma" -ge 1850 ]; then
    is_pps=1
fi

if [ "$is_pps" = "1" ] && [ "$is_charging" = "1" ]; then
    chg_type=3
    [ "$IS_PT" = "1" ] && pps_status="SUPER FAST CHARGING (PPS 9V ATIVO)" || pps_status="SUPER FAST CHARGING (9V PPS ACTIVE)"
elif [ "$is_afc" = "1" ] && [ "$is_charging" = "1" ]; then
    chg_type=2
    [ "$IS_PT" = "1" ] && pps_status="FAST CHARGING (15W AFC/QC 9V)" || pps_status="FAST CHARGING (15W AFC/QC 9V)"
elif [ "$is_charging" = "1" ]; then
    chg_type=1
    [ "$IS_PT" = "1" ] && pps_status="PADRAO (5V Comum)" || pps_status="STANDARD (5V Regular)"
else
    chg_type=0
    [ "$IS_PT" = "1" ] && pps_status="DESCONECTADO (Em Bateria)" || pps_status="DISCONNECTED (On Battery)"
fi

# Potencia instantanea na Bateria (Tensão Dividida ~4.4V)
vbat_int=$((vbat / 10000))
power_mw=$((vbat_int * ibat_ma / 100))

# Calculo de Potencia da Fonte e Cabo por Protocolo Real
if [ "$is_charging" = "1" ]; then
    sign="+"
    p_label_pt="entregues"
    p_label_en="delivered"
    power_w="+$((power_mw / 1000)).$(((power_mw % 1000) / 100))"

    if [ "$chg_type" = "3" ]; then
        # Super Fast Charging PPS (9V, Charge Pump 2:1 ativo)
        tensao_cabo="~9.0 V (USB-C PPS)"
        cabo_ma=$((ibat_ma / 2))
        cabo_label_pt="~$cabo_ma mA (÷2 pelo SP2130)"
        cabo_label_en="~$cabo_ma mA (÷2 by SP2130)"
        power_src_mw=$((power_mw * 103 / 100))
        power_src_w="$((power_src_mw / 1000)).$(((power_src_mw % 1000) / 100))"
        power_src_desc_pt="Consumo Cabo (9V PPS)"
        power_src_desc_en="Cable Draw (9V PPS)"
    elif [ "$chg_type" = "2" ]; then
        # Fast Charging AFC (9V, Buck)
        tensao_cabo="9.0 V (AFC 15W)"
        cabo_ma=$(( (vbat_int * ibat_ma) / 900 ))
        cabo_label_pt="~$cabo_ma mA (Buck 9V)"
        cabo_label_en="~$cabo_ma mA (Buck 9V)"
        power_src_mw=$((power_mw * 118 / 100))
        power_src_w="$((power_src_mw / 1000)).$(((power_src_mw % 1000) / 100))"
        power_src_desc_pt="Consumo AFC (9V)"
        power_src_desc_en="AFC Draw (9V)"
    else
        # Carga Padrao / USB do PC (5V, Buck)
        tensao_cabo="5.0 V (USB PC / Padrão)"
        cabo_ma=$(( (vbat_int * ibat_ma) / 500 ))
        cabo_label_pt="~$cabo_ma mA (USB 5V)"
        cabo_label_en="~$cabo_ma mA (USB 5V)"
        power_src_mw=$((power_mw * 118 / 100))
        power_src_w="$((power_src_mw / 1000)).$(((power_src_mw % 1000) / 100))"
        power_src_desc_pt="Consumo USB (5V)"
        power_src_desc_en="USB Draw (5V)"
    fi
else
    sign="-"
    p_label_pt="consumo"
    p_label_en="consumption"
    power_w="-$((power_mw / 1000)).$(((power_mw % 1000) / 100))"
    tensao_cabo="0.0 V (Sem Cabo)"
    cabo_ma=0
    cabo_label_pt="0 mA (Sem Cabo)"
    cabo_label_en="0 mA (No Cable)"
    power_src_w="0.0"
    power_src_desc_pt="Desconectado"
    power_src_desc_en="Disconnected"
fi

# Verificacao do driver no kernel (aw35615_whole)
if lsmod | grep -qE "aw35615_whole|pps_kp_override"; then
    [ "$IS_PT" = "1" ] && drv_status="ATIVO (Kprobe Universal @cai0fps)" || drv_status="ACTIVE (Universal Kprobe @cai0fps)"
else
    [ "$IS_PT" = "1" ] && drv_status="INATIVO" || drv_status="INACTIVE"
fi

# Estado do Charge Pump Silergy SP2130
if { [ "$chg_type" = "3" ] || [ "$is_pps" = "1" ] || [ "$cp_status_raw" = "Charging" ]; } && [ "$is_charging" = "1" ] && [ "$ibat_ma" -gt 1200 ]; then
    [ "$IS_PT" = "1" ] && cp_state="LIGADO (SP2130 modo 2:1 ativo)" || cp_state="ON (SP2130 2:1 mode active)"
elif { [ "$chg_type" = "3" ] || [ "$is_pps" = "1" ]; } && [ "$is_charging" = "1" ]; then
    [ "$IS_PT" = "1" ] && cp_state="MODULADO (Arrefecimento / Espera)" || cp_state="MODULATED (Cooling / Standby)"
else
    [ "$IS_PT" = "1" ] && cp_state="DESLIGADO" || cp_state="OFF"
fi

if [ "$IS_PT" = "1" ]; then
    echo " [+] Perfil Ativo    : Modo $PROFILE"
    echo " [+] Driver Kernel   : $drv_status"
    echo " [+] Protocolo USB   : $pps_status"
    echo " [+] Charge Pump     : $cp_state"
    echo " [+] Nivel Bateria   : $soc% (Alvo: 100%)"
    echo " [+] Tensao Célula   : $vbat_v V (Bateria 1S Max 4.45V)"
    echo " [+] Corrente Real   : ${sign}${ibat_ma} mA (Bateria)"
    echo " [+] Potencia Divid. : $power_w W ($p_label_pt)"
    if [ "$is_charging" = "1" ]; then
        echo " [+] Potencia Fonte  : $power_src_w W ($power_src_desc_pt)"
        echo " [+] Tensao do Cabo  : $tensao_cabo"
        echo " [+] Corrente Cabo   : $cabo_label_pt"
    else
        echo " [+] Potencia Fonte  : 0.0 W (Desconectado)"
        echo " [+] Tensao do Cabo  : 0.0 V (Sem Cabo)"
        echo " [+] Corrente Cabo   : 0 mA (Sem Cabo)"
    fi
    echo " [+] Temp. Bateria   : $temp_c C"
    echo " [+] Temp. Carcaca   : $quiet_c C (quiet-therm)"
    echo " [+] Nivel Termico   : $cdev26 (0 = Plena Potencia)"
    if [ "$PROFILE" = "ULTRA" ]; then
        echo " [+] Bypass Termico  : ATIVO (Throttling desarmado)"
        echo " [+] Bypass de Tela  : ATIVO (25W liberado com tela ligada)"
    fi
    echo " [!] Uso deste modulo por conta e risco exclusivos do usuario."
else
    echo " [+] Active Profile  : Mode $PROFILE"
    echo " [+] Kernel Driver   : $drv_status"
    echo " [+] USB Protocol    : $pps_status"
    echo " [+] Charge Pump     : $cp_state"
    echo " [+] Battery Level   : $soc% (Target: 100%)"
    echo " [+] Cell Voltage    : $vbat_v V (1S Battery Max 4.45V)"
    echo " [+] Real Current    : ${sign}${ibat_ma} mA (Battery)"
    echo " [+] Divided Power   : $power_w W ($p_label_en)"
    if [ "$is_charging" = "1" ]; then
        echo " [+] Source Power    : $power_src_w W ($power_src_desc_en)"
        echo " [+] Cable Voltage   : $tensao_cabo"
        echo " [+] Cable Current   : $cabo_label_en"
    else
        echo " [+] Source Power    : 0.0 W (Disconnected)"
        echo " [+] Cable Voltage   : 0.0 V (No Cable)"
        echo " [+] Cable Current   : 0 mA (No Cable)"
    fi
    echo " [+] Battery Temp    : $temp_c C"
    echo " [+] Chassis Temp    : $quiet_c C (quiet-therm)"
    echo " [+] Thermal Level   : $cdev26 (0 = Full Power)"
    if [ "$PROFILE" = "ULTRA" ]; then
        echo " [+] Thermal Bypass  : ACTIVE (Throttling disarmed)"
        echo " [+] Screen Bypass   : ACTIVE (25W unlocked with screen on)"
    fi
    echo " [!] Use of this module is at the user's sole risk and responsibility."
fi
echo ""
echo "=================================================="
