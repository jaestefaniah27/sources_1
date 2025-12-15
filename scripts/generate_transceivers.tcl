# generate_transceivers.tcl
# Versión 6.0: AUTO-DESCUBRIMIENTO (System Info Block)

proc create_transceiver_hier { parent_name index } {
  # ... (Esta función NO cambia, es idéntica a la v5.0) ...
  puts "  -> Generando jerarquía: Transceiver_${index}..."
  set hier_name "Transceiver_${index}"
  set current_bd_instance [current_bd_instance .]
  set hier_obj [create_bd_cell -type hier $hier_name]
  current_bd_instance $hier_obj
  set s "_${index}"
  
  set rtl [create_bd_cell -type module -reference CONFIGURABLE_SERIAL_TOP "rtl_core${s}"]
  set gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 "axi_gpio${s}"]
  set_property -dict [list CONFIG.C_IS_DUAL {1} CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_GPIO_WIDTH {27} \
                           CONFIG.C_ALL_INPUTS_2 {1} CONFIG.C_GPIO2_WIDTH {14}] $gpio

  connect_bd_net [get_bd_pins ${gpio}/gpio_io_o] [get_bd_pins ${rtl}/PS_SERIAL_CONFIG_DataRead_ErrorOk_Send_DataIn]
  connect_bd_net [get_bd_pins ${rtl}/PS_out]     [get_bd_pins ${gpio}/gpio2_io_i]

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI
  connect_bd_intf_net [get_bd_intf_pins S_AXI] [get_bd_intf_pins ${gpio}/S_AXI]

  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type rst aresetn
  connect_bd_net [get_bd_pins aclk]    [get_bd_pins ${gpio}/s_axi_aclk] [get_bd_pins ${rtl}/Clk]
  connect_bd_net [get_bd_pins aresetn] [get_bd_pins ${gpio}/s_axi_aresetn] [get_bd_pins ${rtl}/Reset]

  create_bd_pin -dir I RD
  create_bd_pin -dir O TD
  connect_bd_net [get_bd_pins RD] [get_bd_pins ${rtl}/RD]
  connect_bd_net [get_bd_pins TD] [get_bd_pins ${rtl}/TD]

  create_bd_pin -dir O -from 1 -to 0 irq_raw
  connect_bd_net [get_bd_pins ${rtl}/TX_RDY_EMPTY] [get_bd_pins irq_raw]

  current_bd_instance $current_bd_instance
}

proc create_many_transceivers { count ps_name main_xbar_name } {
  puts "------------------------------------------------"
  puts " INICIANDO GENERACIÓN INTELIGENTE (Count: $count)"
  puts "------------------------------------------------"

  # Limpieza
  delete_bd_objs [get_bd_cells -quiet irq_concat]
  delete_bd_objs [get_bd_cells -quiet axi_intc_global]
  delete_bd_objs [get_bd_cells -quiet axi_sys_info]
  delete_bd_objs [get_bd_cells -quiet const_sys_count]

  # --- A. INFRAESTRUCTURA ---
  set ps_cell [get_bd_cells $ps_name]
  if { $ps_cell eq "" } { puts "ERROR: Zynq no encontrado"; return }
  set sys_clk [get_bd_pins $ps_name/pl_clk0]
  
  set rst_cell [get_bd_cells -quiet *rst*]
  if { $rst_cell eq "" } {
      puts "  -> Creando Reset..."
      set rst_cell [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_gen]
      connect_bd_net $sys_clk [get_bd_pins $rst_cell/slowest_sync_clk]
      connect_bd_net [get_bd_pins $ps_name/pl_resetn0] [get_bd_pins $rst_cell/ext_reset_in]
  } else { set rst_cell [lindex $rst_cell 0] }
  set peripheral_aresetn [get_bd_pins -of_objects $rst_cell -filter {NAME=~*peripheral_aresetn}]

  set main_xbar_cell [get_bd_cells -quiet $main_xbar_name]
  if { $main_xbar_cell eq "" } {
      puts "  -> Creando SmartConnect..."
      set main_xbar_cell [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 $main_xbar_name]
      set_property CONFIG.NUM_SI {1} $main_xbar_cell
      connect_bd_net $sys_clk [get_bd_pins $main_xbar_cell/aclk]
      connect_bd_net $peripheral_aresetn [get_bd_pins $main_xbar_cell/aresetn]
      connect_bd_intf_net [get_bd_intf_pins $ps_name/M_AXI_HPM0_FPD] [get_bd_intf_pins $main_xbar_cell/S00_AXI]
  }

  # --- B. CONFIGURACIÓN GLOBAL ---
  
  # Puertos necesarios: N Transceptores + 1 INTC + 1 SystemInfo
  set needed_ports [expr {$count + 2}]
  puts "  -> SmartConnect configurado a $needed_ports puertos."
  set_property CONFIG.NUM_MI $needed_ports $main_xbar_cell

  # IRQ Concat
  set concat [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 irq_concat]
  set_property CONFIG.NUM_PORTS $count $concat

  # INTC
  set edge_val 0
  for {set k 0} {$k < $count} {incr k} {
      set shift [expr {$k * 2}]
      set pattern [expr {2 << $shift}] 
      set edge_val [expr {$edge_val | $pattern}]
  }
  set edge_hex [format "0x%X" $edge_val]

  set intc_global [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 axi_intc_global]
  set_property -dict [list CONFIG.C_IRQ_CONNECTION {1} CONFIG.C_NUM_INTR_INPUTS [expr {$count * 2}] \
                           CONFIG.C_KIND_OF_INTR {0xFFFFFFFF} CONFIG.C_KIND_OF_EDGE $edge_hex] $intc_global

  connect_bd_net $sys_clk [get_bd_pins ${intc_global}/s_axi_aclk]
  connect_bd_net $peripheral_aresetn [get_bd_pins ${intc_global}/s_axi_aresetn]
  
  # Puerto INTC = count (penúltimo)
  set intc_idx [format "%02d" $count]
  connect_bd_intf_net [get_bd_intf_pins ${main_xbar_cell}/M${intc_idx}_AXI] [get_bd_intf_pins ${intc_global}/s_axi]

  # --- SYSTEM INFO BLOCK ---
  puts "  -> Creando Bloque System Info (Hardcoded Count: $count)..."
  set sys_info [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_sys_info]
  set_property -dict [list CONFIG.C_ALL_INPUTS {1} CONFIG.C_GPIO_WIDTH {32}] $sys_info
  
  # Constante con el valor de 'count'
  set const_cnt [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_sys_count]
  set_property -dict [list CONFIG.CONST_VAL $count CONFIG.CONST_WIDTH {32}] $const_cnt
  
  connect_bd_net [get_bd_pins ${const_cnt}/dout] [get_bd_pins ${sys_info}/gpio_io_i]
  connect_bd_net $sys_clk [get_bd_pins ${sys_info}/s_axi_aclk]
  connect_bd_net $peripheral_aresetn [get_bd_pins ${sys_info}/s_axi_aresetn]

  # Puerto SysInfo = count + 1 (último)
  set sys_idx [format "%02d" [expr {$count + 1}]]
  connect_bd_intf_net [get_bd_intf_pins ${main_xbar_cell}/M${sys_idx}_AXI] [get_bd_intf_pins ${sys_info}/S_AXI]


  # --- C. GENERACIÓN DE TRANSCEPTORES ---
  for {set i 0} {$i < $count} {incr i} {
    delete_bd_objs [get_bd_cells -quiet "Transceiver_$i"]
    create_transceiver_hier "" $i
    set cell "Transceiver_$i"
    
    connect_bd_net $sys_clk [get_bd_pins ${cell}/aclk]
    connect_bd_net $peripheral_aresetn [get_bd_pins ${cell}/aresetn]
    
    set mi_idx [format "%02d" $i]
    connect_bd_intf_net [get_bd_intf_pins ${main_xbar_cell}/M${mi_idx}_AXI] [get_bd_intf_pins ${cell}/S_AXI]
    connect_bd_net [get_bd_pins ${cell}/irq_raw] [get_bd_pins ${concat}/In${i}]

    if { $i < 13 } {
        make_bd_pins_external [get_bd_pins ${cell}/RD]
        set_property name "UART_${i}_RX" [get_bd_ports RD_0]
        make_bd_pins_external [get_bd_pins ${cell}/TD]
        set_property name "UART_${i}_TX" [get_bd_ports TD_0]
    } else {
        set tie [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 "tie_idle_${i}"]
        set_property CONFIG.CONST_VAL {1} $tie
        connect_bd_net [get_bd_pins ${tie}/dout] [get_bd_pins ${cell}/RD]
    }
  }

  connect_bd_net [get_bd_pins ${concat}/dout] [get_bd_pins ${intc_global}/intr]
  connect_bd_net [get_bd_pins ${intc_global}/irq] [get_bd_pins ${ps_name}/pl_ps_irq0]

  # --- D. DIRECCIONES ---
  puts "  -> Asignando Direcciones..."
  set base 0xA0000000
  set stride 0x1000
  set seg "${ps_name}/Data"

  # Transceptores
  for {set i 0} {$i < $count} {incr i} {
      set addr [expr {$base + ($i * $stride)}]
      assign_bd_address -target_address_space $seg [get_bd_addr_segs Transceiver_${i}/*/S_AXI/Reg] -force -offset [format "0x%08X" $addr] -range 4K
  }
  
  # INTC (Tras los transceptores)
  set intc_addr [expr {$base + ($count * $stride)}]
  assign_bd_address -target_address_space $seg [get_bd_addr_segs axi_intc_global/S_AXI/Reg] -force -offset [format "0x%08X" $intc_addr] -range 4K

  # SYSTEM INFO (Dirección Fija y Conocida: 0xA0020000)
  # Usamos una dirección alta fija para que el software siempre sepa dónde mirar primero.
  set sys_info_addr 0xA0020000
  assign_bd_address -target_address_space $seg [get_bd_addr_segs axi_sys_info/S_AXI/Reg] -force -offset [format "0x%08X" $sys_info_addr] -range 4K

  puts "LISTO. System Info en 0xA0020000."
}
#source /home/mpsocv2/CONFIGURABLE_TRANSCEIVER_SERIAL/CONFIGURABLE_TRANSCEIVER_SERIAL.srcs/sources_1/scripts/generate_transceivers.tcl
#create_many_transceivers 14 "zynq_ultra_ps_e_0" "axi_smc"