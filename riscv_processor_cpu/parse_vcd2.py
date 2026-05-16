import sys

def parse_vcd(vcd_path):
    with open(vcd_path, 'r') as f:
        lines = f.readlines()

    id_to_name = {}
    
    idx = 0
    while idx < len(lines):
        line = lines[idx].strip()
        if line.startswith("$var"):
            parts = line.split()
            width = int(parts[2])
            sig_id = parts[3]
            sig_name = parts[4]
            # Track all signals
            id_to_name[sig_id] = (sig_name, width)
        elif line.startswith("$enddefinitions"):
            idx += 1
            break
        idx += 1

    current_time = 0
    state = {}
    
    target_names = [
        'id_ex_mem_read', 'id_ex_rd', 'hazard_rs1', 'hazard_rs2',
        'hazard_pc_write', 'hazard_if_id_write', 'hazard_control_mux',
        'pc_write', 'if_id_write', 'control_mux', 'stall'
    ]

    for idx in range(idx, len(lines)):
        line = lines[idx].strip()
        if not line: continue
        if line.startswith('#'):
            time = int(line[1:])
            # Print state right before we advance to the next time step (if it's around time 0 to 40)
            if current_time <= 40:
                print(f"--- Time {current_time} ---")
                for tid, (name, width) in id_to_name.items():
                    if name in target_names and tid in state:
                        print(f"  {name} = {state[tid]}")
            current_time = time
        elif line[0] in '01xXzZ':
            state[line[1:]] = line[0]
        elif line[0] == 'b':
            parts = line.split()
            state[parts[1]] = parts[0][1:]

    # Last time
    if current_time <= 40:
        print(f"--- Time {current_time} ---")
        for tid, (name, width) in id_to_name.items():
            if name in target_names and tid in state:
                print(f"  {name} = {state[tid]}")

if __name__ == "__main__":
    parse_vcd(sys.argv[1])
