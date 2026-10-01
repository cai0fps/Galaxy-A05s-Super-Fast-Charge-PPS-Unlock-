#!/system/bin/sh
# KernelSU Action Script - Live PPS Status Dashboard por @cai0fps

echo "=================================================="
echo "    GALAXY A05s — PAINEL DE TELEMETRIA PPS"
echo "               por @cai0fps                      "
echo "=================================================="
echo ""

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

# Verificacao do driver no kernel (aw35615_whole)
if lsmod | grep -qE "aw35615_whole|pps_kp_override"; then
    drv_status="ATIVO (Kprobe Universal @cai0fps)"
else
    drv_status="INATIVO"
fi

# Protocolo de Carga via dumpsys battery
chg_line=$(dumpsys battery 2>/dev/null | grep "charger_type:" | head -n 1)
chg_type="${chg_line##* }"
case "$chg_type" in
    3) pps_status="SUPER FAST CHARGING (PPS 25W ATIVO)" ;;
    2) pps_status="FAST CHARGING (15W AFC/QC)" ;;
    1) pps_status="PADRAO (5V Comum)" ;;
    *) [ "$ac_online" = "1" ] && pps_status="CARREGANDO (Padrao)" || pps_status="DESCONECTADO (Em Bateria)" ;;
esac

# Estado do Charge Pump Silergy SP2130
if [ "$chg_type" = "3" ] && [ "$ibat_ma" -gt 1200 ]; then
    cp_state="LIGADO (SP2130 modo 2:1 ativo)"
elif [ "$chg_type" = "3" ]; then
    cp_state="MODULADO (Arrefecimento / Espera)"
else
    cp_state="DESLIGADO"
fi

echo " [+] Driver Kernel   : $drv_status"
echo " [+] Protocolo USB   : $pps_status"
echo " [+] Charge Pump     : $cp_state"
echo " [+] Nivel Bateria   : $soc% (Alvo: 100%)"
echo " [+] Tensao Bateria  : $vbat_v V"
echo " [+] Corrente Real   : +$ibat_ma mA"
echo " [+] Temp. Bateria   : $temp_c C"
echo " [+] Temp. Carcaca   : $quiet_c C (quiet-therm)"
echo " [+] Thermal Level   : $cdev26 (0 = Plena Potencia)"
echo ""
echo "=================================================="
