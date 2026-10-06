set v30u_regs [add_to_collection \
                   [get_keepers -nowarn {*|v30u_eu:*|*}] \
                   [get_keepers -nowarn {*|v30u_biu:*|*}]]

set v30bus_ce [get_keepers -nowarn {*|deadang_v30:*|addr_lat[*] *|deadang_v30:*|be_lat[*] \
                                    *|deadang_v30:*|dout_lat[*] *|deadang_v30:*|t_state[*] \
                                    *|deadang_v30:*|lat_type[*] *|deadang_v30:*|addr_valid \
                                    *|deadang_v30:*|a0_lat *|deadang_v30:*|inta_prev \
                                    *|deadang_v30:*|inta_second}]
if {[get_collection_size $v30bus_ce] > 0} {
    set v30u_regs [add_to_collection $v30u_regs $v30bus_ce]
}
if {[get_collection_size $v30u_regs] > 0} {
    set_multicycle_path -setup 4 -from $v30u_regs -to $v30u_regs
    set_multicycle_path -hold  3 -from $v30u_regs -to $v30u_regs
    post_message -type info "deadang.sdc: CE multicycle 4/3 en [get_collection_size $v30u_regs] registros V30"
}

set v30bus_cap [get_registers -nowarn {*|deadang_v30:*|bs_q[*]}]
if {[get_collection_size $v30u_regs] > 0 && [get_collection_size $v30bus_cap] > 0} {
    set_multicycle_path -setup 4 -from $v30u_regs -to $v30bus_cap
    set_multicycle_path -hold  3 -from $v30u_regs -to $v30bus_cap
}
