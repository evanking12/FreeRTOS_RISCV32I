# Fast simulation TCL script
# Runs for shorter time - good for debugging

set curr_wave [current_wave_config]
if { [string length $curr_wave] == 0 } {
  if { [llength [get_objects]] > 0} {
    add_wave /
    set_property needs_save false [current_wave_config]
  } else {
     send_msg_id Add_Wave-1 WARNING "No top level signals found."
  }
}

# Run for 50ms (much faster than 1000ms)
# - trap_test should complete in <10ms
# - context_test should show results in <20ms
puts "Running simulation for 50ms..."
run 50ms

puts ""
puts "=== Simulation complete (50ms) ==="

