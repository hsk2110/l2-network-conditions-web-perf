import csv
import operator as op
import os
import re
import sys
from pathlib import Path

# index        0
fieldnames = ['exp_parameters']
# index                    1              2              3           4
environment_parameters = ['dl_capacity', 'ul_capacity', 'dl_delay', 'ul_delay']
# index            5     6      7      8      9      10     11   12     13     14         15
rpm_parameters = ['id', 'inc', 'inp', 'mad', 'mnp', 'mps', 'p', 'ptc', 'sdt', 'timeout', 'tmp']

# index            16                       17                          18               19                20                 21                 22                 23                    24            25            26          27
dl_test_output = ['dl_stable_throughput',  'dl_stable_responsiveness', 'dl_throughput', 'dl_connections', 'dl_max_path_mtu', 'dl_max_send_mss', 'dl_max_recv_mss', 'dl_retransmissions', 'dl_reorder', 'dl_avg_rtt', 'dl_rpm_p', 'dl_rpm_trimmed']
# index            28                       29                          30               31                32                 33                 34                 35                    36            37            38          39
ul_test_output = ['ul_stable_throughput',  'ul_stable_responsiveness', 'ul_throughput', 'ul_connections', 'ul_max_path_mtu', 'ul_max_send_mss', 'ul_max_recv_mss', 'ul_retransmissions', 'ul_reorder', 'ul_avg_rtt', 'ul_rpm_p', 'ul_rpm_trimmed']
# index               40              41
final_test_output = ['final_rpm_p', 'final_rpm_trimmed']
# index                  42               43                     44            45                  46             47
relative_test_output = ['ub_base_rpm_p', 'ub_base_rpm_trimmed', 'base_rpm_p', 'base_rpm_trimmed', 'wc_effect_p', 'wc_effect_trimmed']
# index  48           
misc = ['iteration']

fieldnames = fieldnames + environment_parameters + rpm_parameters + dl_test_output + ul_test_output + final_test_output + relative_test_output + misc

datalist = []

def initData(data):
    for i in range(0, 5):
        data[fieldnames[i]] = ''
    data[fieldnames[5]] = '1'       #id
    data[fieldnames[6]] = '1'       #inc
    data[fieldnames[7]] = '1'       #inp
    data[fieldnames[8]] = '4'       #mad
    data[fieldnames[9]] = '16'      #mnp
    data[fieldnames[10]] = '100'    #mps
    data[fieldnames[11]] = '90'     #p
    data[fieldnames[12]] = '0.05'   #ptc
    data[fieldnames[13]] = '5'      #sdt
    data[fieldnames[14]] = '20'     #timeout
    data[fieldnames[15]] = '5'      #tmp
    data[fieldnames[16]] = 'True'   #dl_stable_throughput
    data[fieldnames[17]] = 'True'   #dl_stable_responsiveness
    data[fieldnames[28]] = 'True'   #ul_stable_throughput
    data[fieldnames[29]] = 'True'   #ul_stable_responsiveness


# ...existing code...
import csv
import os
import sys
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

# ...existing code...

def parseFile(filename):
    data = {}
    initData(data)
    download = True
    readResults = False
    f = fieldnames  # local alias for slightly faster lookups

    with open(filename, "r") as file:
        for raw_line in file:
            line = raw_line.strip()
            if not line:
                continue

            if not readResults:
                if line.startswith("Testing"):
                    split_line = line.split()
                    if "environment" in line:
                        for i in range(0, 5):
                            data[f[i]] = split_line[i + 3]
                    else:
                        data[f[0]] += " " + split_line[3]
                        data[split_line[3]] = split_line[4]
                        data[f[0]] += " " + split_line[4]
                elif line.startswith("Unbounded Baseline RPM:"):
                    split_line = line.split()
                    if "Trimmed" in line:
                        data[f[43]] = split_line[3]
                    else:
                        data[f[42]] = split_line[3]
                elif line.startswith("Baseline RPM:"):
                    split_line = line.split()
                    if "Trimmed" in line:
                        data[f[45]] = split_line[2]
                    else:
                        data[f[44]] = split_line[2]
                elif line.startswith("iteration"):
                    split_line = line.split()
                    data[f[48]] = split_line[1]
                elif line == "Results:":
                    readResults = True
            else:
                if line.startswith("Download"):
                    download = True
                elif line.startswith("Upload"):
                    download = False
                elif line.startswith("Note"):
                    if "responsiveness" in line:
                        data[f[17] if download else f[29]] = "False"
                    if "throughput" in line:
                        data[f[16] if download else f[28]] = "False"
                elif line.startswith("Throughput"):
                    split_line = line.split()
                    if download:
                        data[f[18]] = split_line[1]
                        data[f[19]] = split_line[6]
                    else:
                        data[f[30]] = split_line[1]
                        data[f[31]] = split_line[6]
                elif "MTU" in line:
                    split_line = line.split()
                    data[f[20] if download else f[32]] = split_line[3]
                elif "Send" in line:
                    split_line = line.split()
                    data[f[21] if download else f[33]] = split_line[3]
                elif "Recv" in line:
                    split_line = line.split()
                    data[f[22] if download else f[34]] = split_line[3]
                elif "Retransmissions" in line:
                    split_line = line.split()
                    data[f[23] if download else f[35]] = split_line[2]
                elif "Reorderings" in line:
                    split_line = line.split()
                    data[f[24] if download else f[36]] = split_line[2]
                elif line.startswith("Average RTT:"):
                    split_line = line.split()
                    data[f[25] if download else f[37]] = split_line[2]
                elif line.startswith("RPM"):
                    split_line = line.split()
                    if "Trimmed" in line:
                        data[f[27] if download else f[39]] = split_line[1]
                    else:
                        data[f[26] if download else f[38]] = split_line[1]
                elif line.startswith("Final"):
                    split_line = line.split()
                    if "Trimmed" in line:
                        data[f[41]] = split_line[2]
                    else:
                        data[f[40]] = split_line[2]
                elif line.startswith("Working"):
                    split_line = line.split()
                    if "Trimmed" in line:
                        data[f[47]] = split_line[5][:-1]
                        readResults = False
                    else:
                        data[f[46]] = split_line[5][:-1]

    return data

# if you work on the server you have to edit the path!!!! (dont forget like last time!)
measurement_folder = Path(sys.argv[1])
csvfile = measurement_folder / "output.csv"

files = [p for p in measurement_folder.rglob("test_output.log") if p.is_file()]

with ThreadPoolExecutor(max_workers=min(32, (os.cpu_count() or 1) + 4)) as ex:
    datalist = list(ex.map(parseFile, files))

# write the datalist into the csv file
with open(csvfile, "w", newline="") as f_out:
    writer = csv.DictWriter(f_out, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(datalist)

print("created csv")
# ...existing code...