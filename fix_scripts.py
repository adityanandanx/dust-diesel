import os
import glob

files = glob.glob('scenes/vehicles/cars/*.tscn')

for file in files:
    with open(file, 'r') as f:
        lines = f.readlines()
        
    has_script_def = False
    for line in lines:
        if 'path="res://scripts/car/car_controller.gd"' in line:
            has_script_def = True
            break
            
    if not has_script_def:
        # Find the last ext_resource
        last_ext_idx = -1
        for i, line in enumerate(lines):
            if line.startswith('[ext_resource'):
                last_ext_idx = i
                
        lines.insert(last_ext_idx + 1, '[ext_resource type="Script" path="res://scripts/car/car_controller.gd" id="car_ctrl"]\n')
        
    # Find the VehicleBody3D root node
    for i, line in enumerate(lines):
        if line.startswith('[node') and 'type="VehicleBody3D"' in line:
            # Check if next lines already have script
            j = i + 1
            has_script = False
            while j < len(lines) and not lines[j].startswith('['):
                if lines[j].startswith('script ='):
                    has_script = True
                    break
                j += 1
            if not has_script:
                lines.insert(i + 1, 'script = ExtResource("car_ctrl")\n')
            break
            
    with open(file, 'w') as f:
        f.writelines(lines)
        
print("Done fixing scripts.")
