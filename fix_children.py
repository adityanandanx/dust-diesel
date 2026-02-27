import os
import glob

files = glob.glob('scenes/vehicles/cars/*.tscn')

exts_to_add = [
    ('res://scripts/car/car_damage.gd', 'car_dmg'),
    ('res://scripts/network/network_sync.gd', 'net_sync')
]

for file in files:
    with open(file, 'r') as f:
        lines = f.readlines()
        
    for path, eid in exts_to_add:
        found = False
        for line in lines:
            if f'path="{path}"' in line:
                found = True
                break
        if not found:
            last_ext = -1
            for i, line in enumerate(lines):
                if line.startswith('[ext_resource'):
                    last_ext = i
            lines.insert(last_ext + 1, f'[ext_resource type="Script" path="{path}" id="{eid}"]\n')

    # Fix nodes
    fixup = [
        ('name="DamageSystem"', 'car_dmg'),
        ('name="NetworkSync"', 'net_sync')
    ]
    
    for i in range(len(lines)):
        for node_tag, eid in fixup:
            if lines[i].startswith('[node ') and node_tag in lines[i]:
                # check if it already has script
                j = i + 1
                has_script = False
                while j < len(lines) and not lines[j].startswith('['):
                    if lines[j].startswith('script ='):
                        has_script = True
                        break
                    j += 1
                if not has_script:
                    lines.insert(i + 1, f'script = ExtResource("{eid}")\n')

    with open(file, 'w') as f:
        f.writelines(lines)
        
print("Fixed child scripts.")
