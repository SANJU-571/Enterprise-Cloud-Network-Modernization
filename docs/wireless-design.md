# Wireless Design & Topology Analysis

## 1. Site survey (two-floor HQ)

**Objective:** full coverage of every room on both floors with strong signal, no
dead zones and stable performance.

| Factor | Target / approach |
|---|---|
| Signal strength | RSSI ≥ **−67 dBm** at client (voice/video grade) |
| Coverage | Whole floor plan, prioritizing meeting rooms, enclosed offices and high-density zones |
| Interference | Walls, doors, metal shelving, existing electronics |
| Obstacles | Concrete/brick walls modelled as high attenuation |
| Bands | 2.4 GHz for reach, 5 GHz (DFS allowed) for capacity |
| Tooling | Hamina Wireless Planner (predictive), NetSpot / Wi-Fi Analyzer for validation |

**Layout changes made during design**
- Floor 1: brick partitions replaced with drywall, and a second AP added.
- Floor 2: re-planned as open space with glass meeting-room walls, with the AP repositioned.

### Results

| Floor | Area | AP | Avg RSSI | Quality | Obstacles | Recommendation |
|---|---|---|---|---|---|---|
| 1 | Center hall | MR46 | −60 dBm | Excellent | Drywall | Add one more AP |
| 1 | Offices left | MR46 | −67 dBm | Good | Drywall | Raise Tx power slightly |
| 2 | Top left | MR36 | **−70 dBm** | Moderate | Drywall + glass | **Add one more AP** |
| 2 | Right wing | MR36 | −62 dBm | Excellent | Drywall + glass | Optimal |
| 2 | Bottom center | MR36 | −65 dBm | Good | Drywall + glass | Monitor user density |

```bash
python scripts/wifi_survey_report.py network/wireless/site-survey-results.csv
```

### Final recommendations
- **Two APs per floor**, one per zone.
- **Floor 1: Meraki MR46** (4×4:4 MU-MIMO, Wi-Fi 6) for capacity in executive offices.
- **Floor 2: Meraki MR36** (2×2:2 MU-MIMO, Wi-Fi 6) for cost efficiency in open/shared space.
- Ceiling-mounted at 2.5–3 m. DFS channels on 5 GHz. Revalidate with a spectrum analyzer after deployment.

Full RF profile and SSID design: [`network/wireless/ap-plan.yaml`](../network/wireless/ap-plan.yaml).

## 2. SSIDs & security

| SSID | VLAN | Security | Notes |
|---|---|---|---|
| STRATOS-CORP | 10 | WPA3-Enterprise, 802.1X EAP-TLS | Band steering, WMM QoS |
| STRATOS-OPS | 50 | WPA3-Enterprise, PEAP-MSCHAPv2 | |
| STRATOS-GUEST | 60 | WPA3-SAE + captive portal | Client isolation, 10 Mbps cap, internet only |

Further controls: rogue AP detection and containment (WIDS/WIPS), minimum
bitrate 12 Mbps, channel planning 1/6/11 on 2.4 GHz, Tx power min/max bounds to
avoid over-coverage, and WPS/UPnP disabled.

## 3. Measuring performance (wired + wireless)

| Metric | Purpose | Target |
|---|---|---|
| Latency | Delay in data travel | < 100 ms |
| Jitter | Variation in delay | < 30 ms |
| Packet loss | Dropped packets | < 1% |
| Throughput | Actual data rate | Close to link capacity (≥ 80%) |
| Signal strength | Wireless signal power | −30 to −67 dBm |

Tools: Wireshark (packet analysis), iPerf3 (bandwidth), ping (latency),
NetSpot (heatmaps), Wi-Fi Analyzer (interference). `scripts/network_perf.py`
automates ping/iPerf3 runs and logs results to CSV.

Optimization checklist: Cat6/Cat6A cabling, avoid long patch chains, managed
switches only, non-overlapping channels, Wi-Fi 6/6E, AP placement validated by
survey, continuous monitoring.

## 4. Wireless topology comparison

| Topology | Speed | Coverage | Reliability | Key vulnerabilities | Key controls |
|---|---|---|---|---|---|
| **Star** | High with few clients; hub becomes the bottleneck | Range of one AP | Hub is a SPOF | Rogue/evil-twin APs, eavesdropping | WPA3, firmware updates, disable WPS, WIDS |
| **Mesh** | Consistent, but latency grows per hop | Excellent: add nodes | High: self-healing | Larger attack surface, compromised node | Node mutual auth, node-to-node encryption, physical security |
| **Bus** | Degrades with collisions | Limited | Low: single backbone | Every device sees all traffic, MITM | IPsec/VPN everywhere; usually replace |
| **Ring** | Consistent but sequential | Limited by node count | Moderate (dual ring better) | Token theft, single node breaks ring | Per-node encryption, node auth, token monitoring |
| **Tree** | Depends on level in the hierarchy | Large, hierarchical | Moderate: backbone critical | Backbone compromise has wide impact | Firewalls between levels, trust zones, audits |

**Recommendations**
- Home / small office (10–30 devices): **Star**, WPA3, router firewall, WPS/UPnP off.
- Large homes, campuses, warehouses, outdoor: **Mesh**, enterprise-grade (Meraki/Ubiquiti), WPA3-Enterprise, WIDS.
- **Enterprises (this project): hybrid Star + Tree**. APs star off access switches, which form a tree to a redundant core. Use 802.1X EAP-TLS, VLAN + firewall segmentation, and SIEM monitoring.

Baseline for every topology: WPA3 (or WPA2-Enterprise fallback), AES only (no
WEP/TKIP), network and host firewalls, IoT/guest isolation, WIDS/WIPS + SIEM,
regular firmware updates, and default credentials changed.
