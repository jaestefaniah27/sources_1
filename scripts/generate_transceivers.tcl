# generate_transceivers.tcl
# -------------------------------------------------------------------------
# Generador de Transceptores UART + Infraestructura + MAPA DE MEMORIA ORDENADO
# -------------------------------------------------------------------------

# --- FUNCIÓN 1: Crear Celda de Transceptor (Lite) ---
proc create_transceiver_hier { parent_name index } {
  puts "  -> Generando jerarquía: Transceiver_${index}..."
  
  set hier_name "Transceiver_${index}"
  set current_bd_instance [current_bd_instance .]
  set hier_obj [create_bd_cell -type hier $hier_name]
  current_bd_instance $hier_obj

  set s "_${index}"

  # 1. GPIOs (Nombres con sufijo para evitar conflictos globales)
  set gpio_setup [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 "gpio_setup${s}"]
  set_property -dict [list CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_GPIO_WIDTH {32}] $gpio_setup

  set gpio_rx [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 "gpio_rx${s}"]
  set_property -dict [list CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_GPIO_WIDTH {2}] $gpio_rx

  set gpio_tx [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 "gpio_tx${s}"]
  set_property -dict [list CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_GPIO_WIDTH {10}] $gpio_tx

  set gpio_out [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 "gpio_out${s}"]
  set_property -dict [list CONFIG.C_ALL_INPUTS {1} CONFIG.C_GPIO_WIDTH {14}] $gpio_out

  # 2. RTL Core
  set rtl [create_bd_cell -type module -reference CONFIGURABLE_SERIAL_TOP "rtl_core${s}"]

  # 3. SmartConnect Interno
  set local_xbar [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 "xbar_internal${s}"]
  set_property CONFIG.NUM_MI {4} $local_xbar
  set_property CONFIG.NUM_SI {1} $local_xbar

  # 4. Conexiones Internas
  connect_bd_net [get_bd_pins ${gpio_setup}/gpio_io_o] [get_bd_pins ${rtl}/PS_SERIAL_CONFIG]
  connect_bd_net [get_bd_pins ${gpio_rx}/gpio_io_o]    [get_bd_pins ${rtl}/PS_RX_DataRead_ErrorOk]
  connect_bd_net [get_bd_pins ${gpio_tx}/gpio_io_o]    [get_bd_pins ${rtl}/PS_TX_DataIn_Send]
  connect_bd_net [get_bd_pins ${rtl}/PS_out]           [get_bd_pins ${gpio_out}/gpio_io_i]

  # 5. Conexiones AXI Internas
  connect_bd_intf_net [get_bd_intf_pins ${local_xbar}/M00_AXI] [get_bd_intf_pins ${gpio_setup}/S_AXI]
  connect_bd_intf_net [get_bd_intf_pins ${local_xbar}/M01_AXI] [get_bd_intf_pins ${gpio_rx}/S_AXI]
  connect_bd_intf_net [get_bd_intf_pins ${local_xbar}/M02_AXI] [get_bd_intf_pins ${gpio_tx}/S_AXI]
  connect_bd_intf_net [get_bd_intf_pins ${local_xbar}/M03_AXI] [get_bd_intf_pins ${gpio_out}/S_AXI]

  # 6. Pines Exteriores
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI
  connect_bd_intf_net [get_bd_intf_pins S_AXI] [get_bd_intf_pins ${local_xbar}/S00_AXI]

  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type rst aresetn
  set clk_pin [get_bd_pins aclk]
  set rst_pin [get_bd_pins aresetn]

  connect_bd_net $clk_pin [get_bd_pins ${local_xbar}/aclk]
  connect_bd_net $clk_pin [get_bd_pins ${gpio_setup}/s_axi_aclk]
  connect_bd_net $clk_pin [get_bd_pins ${gpio_rx}/s_axi_aclk]
  connect_bd_net $clk_pin [get_bd_pins ${gpio_tx}/s_axi_aclk]
  connect_bd_net $clk_pin [get_bd_pins ${gpio_out}/s_axi_aclk]
  connect_bd_net $clk_pin [get_bd_pins ${rtl}/Clk]

  connect_bd_net $rst_pin [get_bd_pins ${local_xbar}/aresetn]
  connect_bd_net $rst_pin [get_bd_pins ${gpio_setup}/s_axi_aresetn]
  connect_bd_net $rst_pin [get_bd_pins ${gpio_rx}/s_axi_aresetn]
  connect_bd_net $rst_pin [get_bd_pins ${gpio_tx}/s_axi_aresetn]
  connect_bd_net $rst_pin [get_bd_pins ${gpio_out}/s_axi_aresetn]
  connect_bd_net $rst_pin [get_bd_pins ${rtl}/Reset]

  create_bd_pin -dir I RD
  create_bd_pin -dir O TD
  connect_bd_net [get_bd_pins RD] [get_bd_pins ${rtl}/RD]
  connect_bd_net [get_bd_pins TD] [get_bd_pins ${rtl}/TD]

  create_bd_pin -dir O -from 1 -to 0 irq_raw
  connect_bd_net [get_bd_pins ${rtl}/TX_RDY_EMPTY] [get_bd_pins irq_raw]

  current_bd_instance $current_bd_instance
}

# --- FUNCIÓN 2: Generación del Sistema Completo ---
proc create_many_transceivers { count ps_name main_xbar_name } {
  puts "------------------------------------------------"
  puts " INICIANDO AUTOMATIZACIÓN COMPLETA ($count TRANSCEPTORES)"
  puts "------------------------------------------------"

  # 1. Limpieza
  if { [get_bd_cells -quiet irq_concat] ne "" } { delete_bd_objs [get_bd_cells irq_concat] }
  if { [get_bd_cells -quiet axi_intc_global] ne "" } { delete_bd_objs [get_bd_cells axi_intc_global] }

  # ----------------------------------------------------------------
  # A. GESTIÓN DE INFRAESTRUCTURA
  # ----------------------------------------------------------------
  set ps_cell [get_bd_cells $ps_name]
  if { $ps_cell eq "" } { puts "ERROR CRÍTICO: No se encuentra '$ps_name'."; return }
  
  set sys_clk [get_bd_pins $ps_name/pl_clk0]
  set sys_resetn [get_bd_pins $ps_name/pl_resetn0]

  # Reset
  set rst_name "rst_ps8_0_99M"
  set sys_rst_cell [get_bd_cells -quiet $rst_name]
  if { $sys_rst_cell eq "" } {
      puts "  -> INFRA: Creando Processor System Reset..."
      set sys_rst_cell [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 $rst_name]
      connect_bd_net $sys_clk [get_bd_pins $sys_rst_cell/slowest_sync_clk]
      connect_bd_net $sys_resetn [get_bd_pins $sys_rst_cell/ext_reset_in]
  }
  set peripheral_aresetn [get_bd_pins $sys_rst_cell/peripheral_aresetn]

  # SmartConnect
  set main_xbar_cell [get_bd_cells -quiet $main_xbar_name]
  if { $main_xbar_cell eq "" } {
      puts "  -> INFRA: Creando SmartConnect Principal..."
      set main_xbar_cell [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 $main_xbar_name]
      set_property CONFIG.NUM_SI {1} $main_xbar_cell
      connect_bd_net $sys_clk [get_bd_pins $main_xbar_cell/aclk]
      connect_bd_net $peripheral_aresetn [get_bd_pins $main_xbar_cell/aresetn]
      connect_bd_intf_net [get_bd_intf_pins $ps_name/M_AXI_HPM0_FPD] [get_bd_intf_pins $main_xbar_cell/S00_AXI]
  }

  # ----------------------------------------------------------------
  # B. CONFIGURACIÓN
  # ----------------------------------------------------------------
  set needed_ports [expr {$count + 1}]
  set_property CONFIG.NUM_MI $needed_ports $main_xbar_cell

  set concat [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 irq_concat]
  set_property CONFIG.NUM_PORTS $count $concat

  # Máscara de Flancos
  set edge_val 0
  for {set k 0} {$k < $count} {incr k} {
      set shift [expr {$k * 2}]
      set pattern [expr {2 << $shift}] 
      set edge_val [expr {$edge_val | $pattern}]
  }
  set edge_hex [format "0x%X" $edge_val]

  # INTC Global
  puts "  -> Creando Controlador de Interrupciones Global..."
  set intc_global [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 axi_intc_global]
  set_property -dict [list \
      CONFIG.C_IRQ_CONNECTION {1} \
      CONFIG.C_NUM_INTR_INPUTS [expr {$count * 2}] \
      CONFIG.C_KIND_OF_INTR {0xFFFFFFFF} \
      CONFIG.C_KIND_OF_EDGE $edge_hex \
  ] $intc_global

  connect_bd_net $sys_clk [get_bd_pins ${intc_global}/s_axi_aclk]
  connect_bd_net $peripheral_aresetn [get_bd_pins ${intc_global}/s_axi_aresetn]
  
  set intc_port_idx [format "%02d" $count]
  connect_bd_intf_net [get_bd_intf_pins ${main_xbar_cell}/M${intc_port_idx}_AXI] [get_bd_intf_pins ${intc_global}/s_axi]

  # ----------------------------------------------------------------
  # C. GENERACIÓN DE TRANSCEPTORES
  # ----------------------------------------------------------------
  for {set i 0} {$i < $count} {incr i} {
    if { [get_bd_cells -quiet "Transceiver_$i"] ne "" } { delete_bd_objs [get_bd_cells "Transceiver_$i"] }

    create_transceiver_hier "" $i
    set cell_name "Transceiver_$i"
    
    connect_bd_net $sys_clk [get_bd_pins ${cell_name}/aclk]
    connect_bd_net $peripheral_aresetn [get_bd_pins ${cell_name}/aresetn]

    set mi_idx [format "%02d" $i]
    connect_bd_intf_net [get_bd_intf_pins ${main_xbar_cell}/M${mi_idx}_AXI] [get_bd_intf_pins ${cell_name}/S_AXI]

    connect_bd_net [get_bd_pins ${cell_name}/irq_raw] [get_bd_pins ${concat}/In${i}]

    make_bd_pins_external [get_bd_pins ${cell_name}/RD]
    set_property name "UART_${i}_RX" [get_bd_ports RD_0]
    make_bd_pins_external [get_bd_pins ${cell_name}/TD]
    set_property name "UART_${i}_TX" [get_bd_ports TD_0]
  }

  # Conexiones Finales IRQ
  connect_bd_net [get_bd_pins ${concat}/dout] [get_bd_pins ${intc_global}/intr]
  connect_bd_net [get_bd_pins ${intc_global}/irq] [get_bd_pins ${ps_name}/pl_ps_irq0]

  # ----------------------------------------------------------------
  # D. ASIGNACIÓN DE DIRECCIONES (MAPA DE MEMORIA ORDENADO)
  # ----------------------------------------------------------------
  puts "  -> Asignando Direcciones de Memoria (Base: 0xA0000000)..."
  
  # Dirección base global
  set base_addr 0xA0000000
  set stride    0x00100000 ;# 64KB por Transceptor
  set ps_master_seg "${ps_name}/Data"

  for {set i 0} {$i < $count} {incr i} {
      set curr_base [expr {$base_addr + ($i * $stride)}]
      set cell "Transceiver_$i"
      set s "_${i}"
      
      # 1. Setup (Offset 0x00000)
      set off [format "0x%08X" [expr {$curr_base + 0x00000}]]
      assign_bd_address -target_address_space $ps_master_seg [get_bd_addr_segs ${cell}/gpio_setup${s}/S_AXI/Reg] -force -offset $off -range 4K

      # 2. RX (Offset 0x10000)
      set off [format "0x%08X" [expr {$curr_base + 0x10000}]]
      assign_bd_address -target_address_space $ps_master_seg [get_bd_addr_segs ${cell}/gpio_rx${s}/S_AXI/Reg] -force -offset $off -range 4K

      # 3. TX (Offset 0x20000)
      set off [format "0x%08X" [expr {$curr_base + 0x20000}]]
      assign_bd_address -target_address_space $ps_master_seg [get_bd_addr_segs ${cell}/gpio_tx${s}/S_AXI/Reg] -force -offset $off -range 4K

      # 4. Out (Offset 0x30000)
      set off [format "0x%08X" [expr {$curr_base + 0x30000}]]
      assign_bd_address -target_address_space $ps_master_seg [get_bd_addr_segs ${cell}/gpio_out${s}/S_AXI/Reg] -force -offset $off -range 4K
  }

  # 5. INTC Global (Al final de todos)
  set intc_base [expr {$base_addr + ($count * $stride)}]
  set off [format "0x%08X" $intc_base]
  assign_bd_address -target_address_space $ps_master_seg [get_bd_addr_segs axi_intc_global/S_AXI/Reg] -force -offset $off -range 4K

  puts "------------------------------------------------"
  puts " GENERACIÓN Y MAPEADO COMPLETADOS EXITOSAMENTE."
  puts "------------------------------------------------"
}
#source /home/mpsocv2/CONFIGURABLE_TRANSCEIVER_SERIAL/CONFIGURABLE_TRANSCEIVER_SERIAL.srcs/sources_1/scripts/generate_transceivers.tcl
#create_many_transceivers 14 "zynq_ultra_ps_e_0" "axi_smc"