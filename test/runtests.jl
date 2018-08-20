using Test, Unicode
Base.include(@__MODULE__, joinpath(Sys.BINDIR, "..", "share", "julia", "test", "testhelpers", "FakePTYs.jl"))
import .FakePTYs: open_fake_pty

slave, master = open_fake_pty()

CTRL_C = '\x03'

# Script that we want the REPL to execute, here simply st for Pkg REPLMode
test_script = """
using ReplMaker

function parse_to_expr(s)
    quote Meta.parse(\$s) end
end

initrepl(parse_to_expr, 
         prompt_text="Expr> ",
         prompt_color = :blue, 
         start_key=')', 
         mode_name="Expr_mode")

) x + 1

"""*CTRL_C


function run_test()
    slave, master = open_fake_pty()
    # Start a julia process
    p = run(`$(Base.julia_cmd()) --history-file=no --startup-file=no`, slave, slave, slave; wait=false)
    
    # Read until the prompt
    readuntil(master, "julia>", keep=true)
    done = false
    repl_output_buffer = IOBuffer()

    # A task that just keeps reading the output
    @async begin
        while true
            done && break
            write(repl_output_buffer, readavailable(master))
        end
    end

    # Execute our "script"
    for l in split(test_script, '\n'; keepempty=false)
        write(master, l, '\n')
    end

    # Let the REPL exit
    write(master, "exit()\n")
    wait(p)
    done = true

    # Gather the output
    repl_output = String(take!(repl_output_buffer))
    println(repl_output)
    return split(repl_output, '\n'; keepempty=false)
end


out = run_test();



@test out[end-5] == "\e[?2004h\r\e[0K\e[34m\e[1mExpr> \e[0m\e[0m\r\e[6C\r\e[6C\r\e[0K\e[34m\e[1mExpr> \e[0m\e[0m\r\e[6C\r\e[6C^C\r"
