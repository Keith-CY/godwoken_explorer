use rustler::{Encoder, Env, Error, Term};
use std::str;
mod moleculec_type;
use moleculec_type::DepositionLockArgs;
use molecule::prelude::Entity;

mod atoms {
    rustler::rustler_atoms! {
        atom ok;
        //atom error;
        //atom __true__ = "true";
        //atom __false__ = "false";
    }
}

rustler::rustler_export_nifs! {
    "Elixir.Godwoken.NifTest",
    [
        ("add", 2, add),
        ("parse_deposition_lock_args", 1, parse_deposition_lock_args)
    ],
    None
}

fn add<'a>(env: Env<'a>, args: &[Term<'a>]) -> Result<Term<'a>, Error> {
    let num1: i64 = args[0].decode()?;
    let num2: i64 = args[1].decode()?;

    Ok((atoms::ok(), num1 + num2).encode(env))
}

fn parse_deposition_lock_args<'a>(env: Env<'a>, args: &[Term<'a>]) -> Result<Term<'a>, Error> {
    let hex_string: &str = args[0].decode()?;
    let witness_args = hex::decode(hex_string).unwrap();
    println!("{:?}", witness_args);
    Ok(DepositionLockArgs::from_slice(&witness_args).unwrap().cancel_timeout().as_slice().encode(env))
}
