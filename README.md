# StealthConnect

Tooling to automate the process of obscuring yourself while capturing network traffic and connecting to foreign APs.

## Installation

Clone the repository and run the setup script:

```bash
git clone https://github.com/wellatleastitried/StealthConnect.git
chmod +x setup.sh
./setup.sh
```

## Usage

Automate the process of obscuring yourself while capturing network traffic - listening for a handshake:

```bash
# Gives the usage information
stealthDeauth -h
```

Obscure yourself while connecting to a foreign AP:

```bash
stealthConnect
```

Revert altered configurations from `stealthConnect`:

```bash
stealthDisconnect
```

## Notice

This script is provided for educational and authorized security testing only.
You are solely responsible for ensuring that your use of this script complies
with all applicable laws, regulations, and terms of service.

The author assumes NO LIABILITY and NO RESPONSIBILITY for any misuse, damage,
unauthorized access, disruption of service, or illegal activity resulting from
the use of this script.

By using this script, you acknowledge that:
- You understand the potential impact of the actions it performs;
- You have explicit permission to use it in the target environment;
- You accept full responsibility for any consequences arising from its use.

If you do not agree to these terms, you are prohibited from using this script.

## Notice 2

As long as this message remains here, I have not done any testing on these scripts yet - so they may or may not work as intended.
