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

# Metricas brutas do hardware
vbat=$(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null || echo 0)
ibat=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null || echo 0)
temp=$(cat /sys/class/power_supply/battery/temp 2>/dev/null || echo 0)
soc=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo 0)
ac_online=$(cat /sys/class/power_supply/battery/online 2>/dev/null || echo 0)
cdev26=$(cat /sys/class/thermal/cooling_device26/cur_state 2>/dev/null || echo 0)
quiet_t=$(cat /sys/class/thermal/thermal_zone19/temp 2>/dev/null || echo 0)

# Calculos matematicos puros sem awk
vbat_v="$((vbat / 1000000)).$(((vbat % 1000000) / 10000))"
ibat_abs=$(( ibat < 0 ? -ibat : ibat ))
ibat_ma="$(( ibat_abs / 1000 ))"
temp_c="$((temp / 10)).$((temp % 10))"
quiet_c="$((quiet_t / 1000)).$(((quiet_t % 1000) / 100))"

# Potencia instantanea na Bateria (Tensão Dividida ~4.4V)
vbat_int=$((vbat / 10000))
power_mw=$((vbat_int * ibat_ma / 100))
power_w="$((power_mw / 1000)).$(((power_mw % 1000) / 100))"

# Potencia na escala de 9V do Carregador PPS (Fonte / Cabo)
power_9v_mw=$((9 * ibat_ma))
power_9v_w="$((power_9v_mw / 1000)).$(((power_9v_mw % 1000) / 100))"
cabo_ma=$((ibat_ma / 2))

# Verificacao do driver no kernel (aw35615_whole)
if lsmod | grep -qE "aw35615_whole|pps_kp_override"; then
    [ "$IS_PT" = "1" ] && drv_status="ATIVO (Kprobe Universal @cai0fps)" || drv_status="ACTIVE (Universal Kprobe @cai0fps)"
else
    [ "$IS_PT" = "1" ] && drv_status="INATIVO" || drv_status="INACTIVE"
fi

# Protocolo de Carga via dumpsys battery
chg_line=$(dumpsys battery 2>/dev/null | grep "charger_type:" | head -n 1)
chg_type="${chg_line##* }"
case "$chg_type" in
    3) [ "$IS_PT" = "1" ] && pps_status="SUPER FAST CHARGING (PPS 25W ATIVO)" || pps_status="SUPER FAST CHARGING (25W PPS ACTIVE)" ;;
    2) [ "$IS_PT" = "1" ] && pps_status="FAST CHARGING (15W AFC/QC)" || pps_status="FAST CHARGING (15W AFC/QC)" ;;
    1) [ "$IS_PT" = "1" ] && pps_status="PADRAO (5V Comum)" || pps_status="STANDARD (5V Regular)" ;;
    *) 
        if [ "$ac_online" = "1" ]; then
            [ "$IS_PT" = "1" ] && pps_status="CARREGANDO (Padrao)" || pps_status="CHARGING (Standard)"
        else
            [ "$IS_PT" = "1" ] && pps_status="DESCONECTADO (Em Bateria)" || pps_status="DISCONNECTED (On Battery)"
        fi
        ;;
esac

# Estado do Charge Pump Silergy SP2130
if [ "$chg_type" = "3" ] && [ "$ibat_ma" -gt 1200 ]; then
    [ "$IS_PT" = "1" ] && cp_state="LIGADO (SP2130 modo 2:1 ativo)" || cp_state="ON (SP2130 2:1 mode active)"
elif [ "$chg_type" = "3" ]; then
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
    echo " [+] Corrente Real   : +$ibat_ma mA (Bateria)"
    echo " [+] Potencia Divid. : $power_w W (Entregue na Bateria)"
    if [ "$chg_type" = "3" ]; then
        echo " [+] Potencia Fonte  : $power_9v_w W (Escala 9V PPS)"
        echo " [+] Tensao do Cabo  : ~9.0 V (USB-C VBUS)"
        echo " [+] Corrente Cabo   : ~$cabo_ma mA (Divisao 2:1)"
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
    echo " [+] Real Current    : +$ibat_ma mA (Battery)"
    echo " [+] Divided Power   : $power_w W (Delivered to Cell)"
    if [ "$chg_type" = "3" ]; then
        echo " [+] Source Power    : $power_9v_w W (9V PPS Scale)"
        echo " [+] Cable Voltage   : ~9.0 V (USB-C VBUS)"
        echo " [+] Cable Current   : ~$cabo_ma mA (2:1 Division)"
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
