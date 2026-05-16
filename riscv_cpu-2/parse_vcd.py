import sys
import re

def parse_vcd(vcd_path, signals_to_track):
    with open(vcd_path, 'r') as f:
        lines = f.readlines()

    id_to_name = {}
    name_to_id = {}
    
    # Parse header
    idx = 0
    while idx < len(lines):
        line = lines[idx].strip()
        if line.startswith("$var"):
            parts = line.split()
            width = int(parts[2])
            sig_id = parts[3]
            sig_name = parts[4]
            if sig_name in signals_to_track:
                id_to_name[sig_id] = (sig_name, width)
                name_to_id[sig_name] = sig_id
        elif line.startswith("$enddefinitions"):
            idx += 1
            break
        idx += 1

    print("Tracking:", name_to_id)

    # Parse dumps
    current_time = 0
    state = {name: 'x' for name in signals_to_track}
    
    while idx < len(lines):
        line = lines[idx].strip()
        if not line:
            idx += 1
            continue
        if line.startswith('#'):
            print(f"Time {current_time}: {state}")
            current_time = int(line[1:])
        elif line[0] in '01xXzZ':
            val = line[0]
            sig_id = line[1:]
            if sig_id in id_to_name:
                state[id_to_name[sig_id][0]] = val
        elif line[0] == 'b':
            parts = line.split()
            val = parts[0][1:]
            sig_id = parts[1]
            if sig_id in id_to_name:
                state[id_to_name[sig_id][0]] = val
        idx += 1

    print(f"Time {current_time}: {state}")

if __name__ == "__main__":
    parse_vcd(sys.argv[1], [
        'hazard_pc_write', 'id_ex_mem_read', 'id_ex_rd', 
        'hazard_rs1', 'hazard_rs2', 'stall'
    ])
