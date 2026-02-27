import os
import glob

files = glob.glob('scenes/vehicles/cars/*.tscn') + ['scenes/vehicles/CarBase.tscn']

for file in files:
    with open(file, 'r') as f:
        lines = f.readlines()
        
    out_lines = []
    skip = False
    for line in lines:
        if line.startswith('[node '):
            if 'name="TopDownCamera"' in line:
                skip = True
            else:
                skip = False
        
        if not skip:
            out_lines.append(line)

    with open(file, 'w') as f:
        f.writelines(out_lines)
        
print("Stripped TopDownCamera from all scenes.")
