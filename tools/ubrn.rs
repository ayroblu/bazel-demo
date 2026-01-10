use clap::Parser;
use ubrn_cli::{cli, Result};

fn main() -> Result<()> {
    let args = cli::CliArgs::parse();
    args.run()
}
