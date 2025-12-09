# add_transceiver.tcl
# Función para crear una instancia completa de tu transceptor
# Uso: create_transceiver_cell <index>
# Ejemplo: create_transceiver_cell 1

proc create_transceiver_cell { index } {
  puts "Creando Transceptor Instancia $index ..."
  
  # 1. Crear Jerarquía para mantener el diagrama limpio
  set hier_name "Transceiver_${index}"
  set current_bd_instance [current_bd_instance .]
  set hier_obj [create_bd_cell -type hier $hier_name]
  current_bd_instance $hier_obj

  # 2. Crear los AXI GPIOs
  # Configuración Serial (GPIO0)
  set gpio_setup [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_setup]
  set_property -dict [list CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_GPIO_WIDTH {32}] $gpio_setup

  # Control RX (GPIO1) - Data Read / Error Ack
  set gpio_rx [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_rx]
  set_property -dict [list CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_GPIO_WIDTH {2}] $gpio_rx

  # Datos TX (GPIO2) - Data In / Send Trigger
  set gpio_tx [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_tx]
  set_property -dict [list CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_GPIO_WIDTH {10}] $gpio_tx

  # Salidas Status (GPIO3) - TX Ready / RX Empty / Data / Errors
  set gpio_out [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_out]
  set_property -dict [list CONFIG.C_ALL_INPUTS {1} CONFIG.C_GPIO_WIDTH {14}] $gpio_out

  # 3. Crear AXI Interrupt Controller (CORREGIDO FLANCO DE BAJADA para RX)
  set intc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 axi_intc]
  # C_KIND_OF_INTR: Bit 0=1 (TX Rising), Bit 1=0 (RX Falling) -> 0xFFFFFFFD
  set_property -dict [list CONFIG.C_IRQ_CONNECTION {1} CONFIG.C_KIND_OF_INTR {0xFFFFFFFD}] $intc

  # 4. Instanciar tu RTL (Asegúrate que el nombre del módulo IP coincide)
  # Cambia 'user.org:user:CONFIGURABLE_SERIAL_TOP:1.0' por el nombre real de tu IP en el catálogo
  set rtl_block [create_bd_cell -type ip -vlnv user.org:user:CONFIGURABLE_SERIAL_TOP:1.0 CONFIGURABLE_SERIAL_0]

  # 5. Conectar Pines Internos (GPIOs <-> RTL)
  # Setup
  connect_bd_net [get_bd_pins axi_gpio_setup/gpio_io_o] [get_bd_pins CONFIGURABLE_SERIAL_0/PS_SERIAL_CONFIG]
  # RX Control
  connect_bd_net [get_bd_pins axi_gpio_rx/gpio_io_o] [get_bd_pins CONFIGURABLE_SERIAL_0/PS_RX_DataRead_ErrorOk]
  # TX Control
  connect_bd_net [get_bd_pins axi_gpio_tx/gpio_io_o] [get_bd_pins CONFIGURABLE_SERIAL_0/PS_TX_DataIn_Send]
  # Status Out
  connect_bd_net [get_bd_pins CONFIGURABLE_SERIAL_0/PS_out] [get_bd_pins axi_gpio_out/gpio_io_i]
  
  # 6. Conectar Interrupciones
  # RTL TX_RDY_EMPTY -> INTC intr
  connect_bd_net [get_bd_pins CONFIGURABLE_SERIAL_0/TX_RDY_EMPTY] [get_bd_pins axi_intc/intr]

  # 7. Exponer Pines al Exterior de la Jerarquía
  # Clock y Reset (Entradas comunes)
  create_bd_pin -dir I -type clk s_axi_aclk
  create_bd_pin -dir I -type rst s_axi_aresetn
  
  # Conectar Clocks internos
  connect_bd_net [get_bd_pins s_axi_aclk] [get_bd_pins axi_gpio_setup/s_axi_aclk]
  connect_bd_net [get_bd_pins s_axi_aclk] [get_bd_pins axi_gpio_rx/s_axi_aclk]
  connect_bd_net [get_bd_pins s_axi_aclk] [get_bd_pins axi_gpio_tx/s_axi_aclk]
  connect_bd_net [get_bd_pins s_axi_aclk] [get_bd_pins axi_gpio_out/s_axi_aclk]
  connect_bd_net [get_bd_pins s_axi_aclk] [get_bd_pins axi_intc/s_axi_aclk]
  connect_bd_net [get_bd_pins s_axi_aclk] [get_bd_pins CONFIGURABLE_SERIAL_0/Clk]

  # Conectar Resets internos
  connect_bd_net [get_bd_pins s_axi_aresetn] [get_bd_pins axi_gpio_setup/s_axi_aresetn]
  connect_bd_net [get_bd_pins s_axi_aresetn] [get_bd_pins axi_gpio_rx/s_axi_aresetn]
  connect_bd_net [get_bd_pins s_axi_aresetn] [get_bd_pins axi_gpio_tx/s_axi_aresetn]
  connect_bd_net [get_bd_pins s_axi_aresetn] [get_bd_pins axi_gpio_out/s_axi_aresetn]
  connect_bd_net [get_bd_pins s_axi_aresetn] [get_bd_pins axi_intc/s_axi_aresetn]
  # Ojo: Tu RTL tiene 'Reset' activo alto o bajo? Asumimos activo alto, invertimos si es necesario
  # Si tu RTL usa reset activo bajo (n), conecta directo. Si usa alto, necesitas un util_vector_logic NOT.
  # Por simplicidad aquí asumimos que conectamos directo (Revisar tu RTL)
  # connect_bd_net [get_bd_pins s_axi_aresetn] [get_bd_pins CONFIGURABLE_SERIAL_0/Reset] 

  # Puertos Físicos (RX/TX)
  create_bd_pin -dir I RD
  create_bd_pin -dir O TD
  connect_bd_net [get_bd_pins RD] [get_bd_pins CONFIGURABLE_SERIAL_0/RD]
  connect_bd_net [get_bd_pins TD] [get_bd_pins CONFIGURABLE_SERIAL_0/TD]

  # Salida de Interrupción (hacia el PS)
  create_bd_pin -dir O -type intr irq
  connect_bd_net [get_bd_pins axi_intc/irq] [get_bd_pins irq]

  # Interfaces AXI (Tenemos que sacarlas fuera para conectarlas al Interconnect principal)
  # Lamentablemente Tcl no deja agrupar interfaces AXI facilmente en un pin de jerarquía automático
  # sin usar Interface Ports, pero podemos dejarlos accesibles.
  
  current_bd_instance $current_bd_instance
  puts "Transceptor $index creado en la jerarquía $hier_name"
}