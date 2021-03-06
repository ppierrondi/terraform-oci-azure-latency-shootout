resource "oci_core_virtual_circuit" "interconnect_virtual_circuit" {
  display_name         = "interconnect-virtual-circuit"
  compartment_id       = var.oci_compartment_ocid
  gateway_id           = var.oci_drg_id
  type                 = "PRIVATE"
  bandwidth_shape_name = "1 Gbps"

  provider_service_id       = var.oci_azure_provider_ocid
  provider_service_key_name = azurerm_express_route_circuit.connect_erc.service_key

  cross_connect_mappings {
    oracle_bgp_peering_ip   = "${var.peering_net}.201/30"
    customer_bgp_peering_ip = "${var.peering_net}.202/30"
  }

  cross_connect_mappings {
    oracle_bgp_peering_ip   = "${var.peering_net}.205/30"
    customer_bgp_peering_ip = "${var.peering_net}.206/30"
  }
}

resource "oci_core_route_table" "interconnect_route_table" {
  display_name   = "interconnect-route-table"
  compartment_id = var.oci_compartment_ocid
  vcn_id         = var.oci_vcn_id

  route_rules {
    network_entity_id = var.oci_igw_id
    destination       = "0.0.0.0/0"
  }

  route_rules {
    network_entity_id = var.oci_drg_id
    destination       = var.arm_vnet_cidr
  }
}

resource "oci_core_route_table_attachment" "interconnect_route_table_attachment" {
  subnet_id      = var.oci_server_subnet_id
  route_table_id = oci_core_route_table.interconnect_route_table.id
}

resource "azurerm_public_ip" "connect_vng_ip" {
  name                = "connect-vng-ip"
  location            = var.arm_resource_group_location
  resource_group_name = var.arm_resource_group_name
  allocation_method   = "Dynamic"
}

data "azurerm_public_ip" "connect_vng_ip" {
  name                = azurerm_public_ip.connect_vng_ip.name
  resource_group_name = var.arm_resource_group_name
}

resource "azurerm_virtual_network_gateway" "conn_vng" {
  name                = "connect-vng"
  location            = var.arm_resource_group_location
  resource_group_name = var.arm_resource_group_name
  type                = "ExpressRoute"
  enable_bgp          = true
  sku                 = var.arm_expressroute_sku

  ip_configuration {
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = var.arm_gw_subnet_id
    public_ip_address_id          = azurerm_public_ip.connect_vng_ip.id
  }
}

resource "azurerm_virtual_network_gateway_connection" "conn_vng_gw" {
  name                = "connect-vng-gw"
  location            = var.arm_resource_group_location
  resource_group_name = var.arm_resource_group_name

  type                         = "ExpressRoute"
  virtual_network_gateway_id   = azurerm_virtual_network_gateway.conn_vng.id
  express_route_circuit_id     = azurerm_express_route_circuit.connect_erc.id
  express_route_gateway_bypass = var.arm_expressroute_sku == "UltraPerformance" ? true : false
}

resource "azurerm_network_security_group" "connect_sg" {
  name                = "connect-securitygroup"
  location            = var.arm_resource_group_location
  resource_group_name = var.arm_resource_group_name

  security_rule {
    name                       = "InboundAllOCI"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.oci_vcn_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "OutboundAll"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_express_route_circuit" "connect_erc" {
  name                  = "oci-connect-expressroute"
  resource_group_name   = var.arm_resource_group_name
  location              = var.arm_resource_group_location
  service_provider_name = "Oracle Cloud FastConnect"
  peering_location      = "London"
  bandwidth_in_mbps     = 1000

  sku {
    tier   = "Local"
    family = "MeteredData"
  }

  allow_classic_operations = false
}

