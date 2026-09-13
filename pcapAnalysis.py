import sys
from pathlib import Path
from collections import Counter
from scapy.all import PcapReader, TCP, IP, IPv6

def extract_established_mss(pcap_path):
    pending_syns = {}  # Key: (src, sport, dst, dport) -> Client MSS
    established_pairs = Counter()

    try:
        with PcapReader(str(pcap_path)) as pcap:
            for pkt in pcap:
                if not pkt.haslayer(TCP):
                    continue

                tcp = pkt[TCP]
                
                # Extract IP addresses (handles both IPv4 and IPv6)
                if pkt.haslayer(IP):
                    src_ip, dst_ip = pkt[IP].src, pkt[IP].dst
                elif pkt.haslayer(IPv6):
                    src_ip, dst_ip = pkt[IPv6].src, pkt[IPv6].dst
                else:
                    continue

                # Parse MSS from TCP options
                mss = None
                for option in tcp.options:
                    if option[0] == "MSS":
                        mss = option[1]
                        break

                # Step 1: Detect Client SYN
                if tcp.flags == "S":  # Pure SYN
                    flow_key = (src_ip, tcp.sport, dst_ip, tcp.dport)
                    pending_syns[flow_key] = mss if mss is not None else "Default (536)"

                # Step 2: Detect Server SYN-ACK (Establishes the connection)
                elif tcp.flags == "SA" or (tcp.flags & 0x12 == 0x12):
                    reverse_key = (dst_ip, tcp.dport, src_ip, tcp.sport)
                    
                    if reverse_key in pending_syns:
                        client_mss = pending_syns.pop(reverse_key)
                        server_mss = mss if mss is not None else "Default (536)"
                        
                        # Store established pair
                        established_pairs[(client_mss, server_mss)] += 1

    except Exception as e:
        print(f"Error processing {pcap_path}: {e}")

    return established_pairs


# Main execution over nested traffic.pcap files
measurement_folder = Path(sys.argv[1])
total_unique_mss = Counter()

for file_path in measurement_folder.rglob("traffic.pcap"):
    if file_path.is_file():
        pcap_mss_counts = extract_established_mss(file_path)
        total_unique_mss.update(pcap_mss_counts)

print("\n--- Summary of Unique Established MSS Pairs ---")
print(f"{'Client MSS':<15} | {'Server MSS':<15} | {'Connection Count'}")
print("-" * 50)
for (c_mss, s_mss), count in total_unique_mss.most_common():
    print(f"{str(c_mss):<15} | {str(s_mss):<15} | {count}")