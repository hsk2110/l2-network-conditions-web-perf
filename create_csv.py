import csv
import operator as op
import os
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
# index  48           49            50
misc = ['iteration', 'start_time', 'end_time']

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


def parseFile (filename):
    
    with open(filename, "r") as file:
        lines = file.readlines()
        data = {}
        initData(data)
        download = True
        readResults = False
        startTime = True
        for line in lines:
            line = line.strip()
            split_line = line.split()
            if not readResults:                        
                if line.startswith("Testing"):                
                    if op.contains(line, "environment"):
                        for i in range(0, 5):
                            data[fieldnames[i]] = split_line[i + 3]
                    else:
                        data[fieldnames[0]] += ' ' + split_line[3]
                        data[split_line[3]] = split_line[4]
                elif op.contains(line, "UTC Go Responsiveness"):
                    if startTime:
                        data[fieldnames[49]] = split_line[0] + ' ' + split_line[1]
                        startTime = False
                    else:
                        data[fieldnames[50]] = split_line[0] + ' ' + split_line[1]
                        startTime = True
                        datalist.append(data)
                        data = {}
                        initData(data)
                elif line.startswith("Unbounded Baseline RPM:"):
                    if op.contains(line, "Trimmed"):
                        data[fieldnames[43]] = split_line[3]
                    else:
                        data[fieldnames[42]] = split_line[3]
                elif line.startswith("Baseline RPM:"):
                    if op.contains(line, "Trimmed"):
                        data[fieldnames[45]] = split_line[2]
                    else:
                        data[fieldnames[44]] = split_line[2]
                elif line.startswith("iteration"):
                    data[fieldnames[48]] = split_line[1]
                elif line == "Results:":
                    readResults = True
            else:
                if line.startswith("Download"):
                    download = True
                elif line.startswith("Upload"):
                    download = False
                elif line.startswith("Note"):
                    if op.contains(line, "responsiveness"):
                        if download:
                            data[fieldnames[17]] = 'False'
                        else:
                            data[fieldnames[29]] = 'False'
                    if op.contains(line, "throughput"):
                        if download:
                            data[fieldnames[16]] = 'False'
                        else:
                            data[fieldnames[28]] = 'False'
                elif line.startswith("Throughput"):
                    if download:
                        data[fieldnames[18]] = split_line[1]
                        data[fieldnames[19]] = split_line[6]
                    else:
                        data[fieldnames[30]] = split_line[1]
                        data[fieldnames[31]] = split_line[6]
                elif op.contains(line, "MTU"):
                    if download:
                        data[fieldnames[20]] = split_line[3]
                    else:
                        data[fieldnames[32]] = split_line[3]
                elif op.contains(line, "Send"):
                    if download:
                        data[fieldnames[21]] = split_line[3]
                    else:
                        data[fieldnames[33]] = split_line[3]
                elif op.contains(line, "Recv"):
                    if download:
                        data[fieldnames[22]] = split_line[3]
                    else:
                        data[fieldnames[34]] = split_line[3]
                elif op.contains(line, "Retransmissions"):
                    if download:
                        data[fieldnames[23]] = split_line[2]
                    else:
                        data[fieldnames[35]] = split_line[2]
                elif op.contains(line, "Reorderings"):
                    if download:
                        data[fieldnames[24]] = split_line[2]
                    else:
                        data[fieldnames[36]] = split_line[2]
                elif line.startswith("Average RTT:"):
                    if download:
                        data[fieldnames[25]] = split_line[2]
                    else:
                        data[fieldnames[37]] = split_line[2]
                elif line.startswith("RPM"):
                    if op.contains(line, "Trimmed"):
                        if download:
                            data[fieldnames[27]] = split_line[1]
                        else:
                            data[fieldnames[39]] = split_line[1]
                    else:
                        if download:
                            data[fieldnames[26]] = split_line[1]
                        else:
                            data[fieldnames[38]] = split_line[1]
                elif line.startswith("Final"):
                    if op.contains(line, "Trimmed"):
                        data[fieldnames[41]] = split_line[2]
                    else:
                        data[fieldnames[40]] = split_line[2]
                elif line.startswith("Working"):
                    if op.contains(line, "Trimmed"):
                        data[fieldnames[47]] = split_line[5][:-1]
                        readResults = False
                    else:
                        data[fieldnames[46]] = split_line[5][:-1]
            
# if you work on the server you have to edit the path!!!! (dont forget like last time!)
measurement_folder = Path(f"{sys.argv[1]}")
csvfile = os.path.join(os.getcwd(), f"{sys.argv[1]}/output.csv")

for file_path in measurement_folder.rglob("test_output.log"):
    if file_path.is_file():
        parseFile(file_path)

# write the datalist into the csv file
with open(csvfile, 'w') as csvfile:
    writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(datalist)

print('created csv')