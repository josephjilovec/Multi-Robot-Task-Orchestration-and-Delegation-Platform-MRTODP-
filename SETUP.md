# MRTODP Setup Guide

## Quick Start

### Using Docker (Recommended)

1. Clone the repository
2. Copy `.env.example` to `.env` and configure
3. Run: `docker-compose -f deploy/docker-compose.yml up -d`

### Manual Setup

#### Prerequisites

- Python 3.10+
- Node.js 18+
- Rust 1.80+
- Julia 1.10.0+
- PostgreSQL 15+
- SQLite3

#### Installation Steps

1. **Python Backend:**
```bash
cd backend/python
pip install -r requirements.txt
```

2. **Rust Scheduler:**
```bash
cd backend/rust
cargo build --release
```

3. **Frontend:**
```bash
cd frontend
npm install
npm start
```

4. **Initialize Database:**
```bash
sqlite3 data/tasks.db < backend/cpp/task_manager/schema.sql
```

5. **Run Services:**
```bash
# Python CLI
cd backend/python
python cli.py define heavy_lifting

# Rust Scheduler
cd backend/rust
./target/release/mrtodp-scheduler
```

## Configuration

Edit `.env` file with your settings:
- Database credentials
- API endpoints
- JWT secrets
- Port configurations

## Troubleshooting

See `docs/setup.md` for detailed troubleshooting steps.

