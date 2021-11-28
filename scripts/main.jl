using DrWatson
@quickactivate "MOEAs"
using Metaheuristics
using HardTestProblems
using LinearAlgebra
using Plots; gr()

include("../src/MOEAs.jl")

function run_algorithm(algorithm, f, bounds)
    res = Metaheuristics.optimize(f, bounds, algorithm)
    res
    
end


function get_problem(problem_idx, problem_type)

    # preferences defined as weights
    weight_points = [[0.2,0.7, 0.1],
                   [0.25, 0.25, 0.5],
                   [0.7, 0.2, 0.1],
                  ]
    # the threshold (cosine distance)
    δ_w = fill(0.1, length(weight_points))

    ref_points = Vector{Float64}[
                                 # [-0.032, 260]
                                ]
    δ_r = fill(0.1, length(ref_points))

    if problem_type == :constrianed        
        constrianed_problems =  [:C1_DTLZ1, :C2_DTLZ2, :C1_DTLZ3, :C3_DTLZ4 ]
        problem = constrianed_problems[problem_idx]
        D = 7
        f, bounds, front = Metaheuristics.TestProblems.get_problem(problem)
        bounds = bounds[:, 1:D]
    elseif problem_type == :unconstrianed
        uncostrianed_problems = [:DTLZ1, :DTLZ2, :DTLZ3, :DTLZ4]
        problem = uncostrianed_problems[problem_idx]
        f, bounds, front = Metaheuristics.TestProblems.get_problem(problem)
    elseif problem_type ==:application

        weight_points = Vector{Float64}[
                                        [0.1, 0.9],
                                        [0.5, 0.5],
                                        [0.8, 0.2]
                                       ]
        δ_w = fill(0.1, length(weight_points))
        rw_problems = [
                       "pressure_vessel",
                       "vibrating_platform",
                       "two_bar_Truss_design_problems",
                       "weldan_beam_design"
                      ]
        f, conf =  get_RW_MOP_problem(rw_problems[problem_idx]);
        bounds = Array([conf[:xmin] conf[:xmax]]')
        # f, bounds, _ = Metaheuristics.TestProblems.get_problem(:ZDT3)
        front = []
    end

    f, bounds, front, weight_points, δ_w, ref_points, δ_r
end

function plot_res(archive, population, weight_points, ref_points)
    M = length(Metaheuristics.fval(population[1]))
    p = plot(xlabel="f₁", ylabel="f₂", zlabel="f₃", dpi=200)

    # plot ref directions
    z_ideal = ideal(population)
    z_nad = nadir(population)
    for (i,w) in enumerate(weight_points)
        t = range(0,1, length=50)
        # scale to axis
        ww =  w .* (z_nad - z_ideal)
        line = z_ideal' .+ t.*ww'

        plot!((line[:,i] for i in 1:M)..., label="", color=:gray, lw=2)
    end


    for r in ref_points
        scatter!(r[1:1], r[2:2], markercolor=:red, label="")
    end

    #= population
    fs = fvals(population)
    scatter!((fs[:,i] for i in 1:M)..., label="Approx. Front", markercolor=:lightgray, markerstrokewidth=0)
    =#

    fs = fvals(archive)
    scatter!((fs[:,i] for i in 1:M)..., label="Preferred solutions", markercolor=:black)

    p
end

function get_parms(d) 

    N = d["N"]
    f, bounds, front, weight_points, δ_w, ref_points, δ_r = get_problem(d["fnum"], d["benchmark"])
    options = Options(f_calls_limit=d["fcalls"],iterations=2d["fcalls"]*N, seed=d["seed"], debug=false)

    if d["basealgorithm"] == :CCMO
        base_algorithm = MOEAs.CCMO_NSGAII(;N = N, options = options)
    elseif d["basealgorithm"] == :SPEA2
        base_algorithm = SPEA2(;N , options = options)
    elseif d["basealgorithm"] == :SMS_EMOA
        base_algorithm = SMS_EMOA(;N , options = options)
    elseif d["basealgorithm"] == :NSGA2
        base_algorithm = NSGA2(;N, options = options)
        #=
        elseif d["basealgorithm"] == :MOEADDE
        nobjectives = d["benchmark"] in [:application] ? 2 : 3
        npartitions = d["benchmark"] in [:application] ? 100 : 12
        weights = gen_ref_dirs(nobjectives, npartitions)
        base_algorithm = MOEAD_DE(weights; options = options)
        =#
    else
        alg = d["basealgorithm"]
        error("Base algorithm $alg is not supported.")
    end
    
    algorithm = MOEAs.ROIs(base_algorithm; weight_points, δ_w, ref_points, δ_r)
    algorithm, f, bounds
end


function main()
    seed = 1
    fnum = collect(1:4)
    benchmark = :application
    basealgorithm =  [:NSGA2, :CCMO, :SPEA2, :SMS_EMOA]
    fcalls = 100_000
    N = 100

    allparams = @strdict seed fnum benchmark basealgorithm fcalls N

    dicts = dict_list(allparams)
    for d = dicts
        @info "Running..."
        display(d)
        algorithm, f, bounds = get_parms(d)
        res = run_algorithm(algorithm, f, bounds)
        archive = algorithm.parameters.archive

        if isempty(archive)
            @warn "Archive is empty (unable satisfy preferences)."
            return
        end

        plt = plot_res(archive, res.population, algorithm.parameters.weight_points,algorithm.parameters.ref_points)

        @info "Saving data and Plot..."

        results = Dict("F" => fvals(archive),
                       "X" => positions(archive),
                       "fmin" => ideal(res.population),
                       "fmax" => nadir(res.population),
                       "benchmark" => d["benchmark"],
                       "fnum" => d["fnum"],
                       "basealgorithm" => d["basealgorithm"],
                       "seed" => d["seed"]
                      )
        wsave(datadir("simulations", savename(d, "bson")), results)
        wsave(plotsdir("simulations/"*string(d["basealgorithm"]), savename(d, "pdf")), plt) 
        @info "Data saved."
    end
end

main()

