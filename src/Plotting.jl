# Plotting functions for lattices and spins on lattices.

function _setup_scene(; show_axis=false, ortho=false)
    fig = Makie.Figure()
    ax = Makie.LScene(fig[1, 1]; show_axis)
    if ortho
        _ = Makie.cam3d!(ax.scene, projectiontype=Makie.Orthographic)
    end
    return fig, ax
end

#=
function plot_lattice!(ax, lattice::Lattice; colors=:Set1_9, markersize=200, linecolor=:grey, linewidth=1.0, kwargs...)
    unique_types = unique(lattice.types)
    colors = Makie.resample_cmap(colors, 9)

    # Plot markers at each site
    pts = Makie.Point3f0.(vec(lattice))
    for (i, type) in enumerate(unique_types)
        bs = findall(isequal(type), lattice.types)
        Makie.scatter!(ax, pts; label=type, color=colors[i], markersize=markersize, kwargs...)
    end

    # For some odd reason, the sites will not appear unless this happens afterwards
    # Plot the unit cell mesh
    plot_cells!(ax, lattice; color=linecolor, linewidth=linewidth)
end

function plot_lattice(lattice::Lattice; kwargs...)
    fig, ax = _setup_scene()
    plot_lattice!(ax, lattice; kwargs...)
    # TODO: Markers are often way too big.
    fig[1, 2] = Makie.Legend(fig, ax, "Species")
    fig
end

"""
    plot_lattice(crystal, latsize=(3,3,3); kwargs...)

Plots a crystal lattice with `latsize` unit cells along each
lattice vector. Other keyword arguments are:

colors=:Set1_9, markersize=20, linecolor=:grey, linewidth=1.0, kwargs...
# Arguments
- `linecolor=:grey`: Sets the colors on the unit cell guide lines
- `linewidth=1.0`  : Sets the width of the unit cell guide lines
- `markersize=20`  : Sets the size of the atomic sites
- `colors=:Set1_9` : Sets the colors used for the atomic sites

Additional keyword arguments are given to `Makie.scatter!` which
draws the points.
"""
plot_lattice(cryst::Crystal, latsize=(3,3,3); kwargs...) = plot_lattice(Lattice(cryst, latsize); kwargs...)


function plot_bonds(lattice::Lattice, ints::Vector{<:AbstractInteractionCPU};
                    colors=:Dark2_8, bondwidth=4, kwargs...)
    fig, ax = _setup_scene()

    # Plot the bonds, all relative to a central atom on the first sublattice
    # TODO: Make selectable in GUI
    b = 1

    colors = Makie.resample_cmap(colors, 8)
    # Sort interactions so that longer bonds are plotted first
    sorted_ints = sort(
        ints, 
        by=int->(
            iszero(length(int.bondtable))
            ? Inf 
            : global_distance(lattice, first(all_bonds(int.bondtable))[1])
        )
    )

    # Plot the lattice
    plot_lattice!(ax, lattice; kwargs...)

    toggles = Vector{Makie.Toggle}()
    labels = Vector{Makie.Label}()
    cent_cell = CartesianIndex(div.(lattice.size .+ 1, 2)...)
    cent_pt = lattice[cent_cell, b]
    for (n, int) in enumerate(sorted_ints)
        if !isa(int, AbstractPairIntCPU)
            continue
        end

        pts = Vector{Makie.Point3f0}()
        for (bond, _) in sublat_bonds(int.bondtable, b)
            new_cell = offsetc(cent_cell, bond.n, lattice.size)
            bond_pt = lattice[new_cell, bond.j]
            push!(pts, Makie.Point3f0(cent_pt))
            push!(pts, Makie.Point3f0(bond_pt))
        end
        if length(pts) == 0
            continue
        end

        color = colors[mod1(n, 8)]
        seg = Makie.linesegments!(pts; linewidth=bondwidth, label=int.label, color=color)
        tog = Makie.Toggle(fig, active=true)
        Makie.connect!(seg.visible, tog.active)
        push!(toggles, tog)
        push!(labels, Makie.Label(fig, int.label))
    end
    Makie.axislegend()
    if length(toggles) > 0
        fig[1, 2] = Makie.grid!(hcat(toggles, labels), tellheight=false)
    end
    fig
end


"""
    plot_bonds(cryst::Crystal, ints, latsize=(3,3,3), infos=SpinInfo[]; kwargs...)

Plot a list of pair interactions defined on a `Crystal`. `latsize` sets how many
unit cells are plotted, and `kwargs` are passed to to `plot_lattice!`.
"""
function plot_bonds(cryst::Crystal, ints::Vector{<:AbstractInteraction}, latsize=(3,3,3);
                    kwargs...)
    latsize = collect(Int64.(latsize))
    lattice = Lattice(cryst, latsize)
    (all_infos, _) = propagate_site_info!(cryst, SpinInfo[])
    ℋ = Interactions(ints, cryst, all_infos)
    pair_ints = vcat(ℋ.heisenbergs, ℋ.diag_coups, ℋ.gen_coups)
    plot_bonds(lattice, pair_ints; kwargs...)
end


"""
    plot_bonds(sys::System; kwargs...)

Plot all pair interactions appearing in `sys.interactions_union`, on the
underlying crystal lattice. `kwargs` are passed to `plot_lattice!`.
"""
@inline function plot_bonds(sys::System; kwargs...)
    ℋ = sys.interactions_union
    pair_ints = vcat(ℋ.heisenbergs, ℋ.diag_coups, ℋ.gen_coups)
    plot_bonds(sys.crystal, pair_ints; kwargs...)
end

"""
    plot_all_bonds(crystal::Crystal, max_dist, latsize=(3,3,3); kwargs...)

Plot all bond equivalency classes present in `crystal` up to a maximum
bond length of `max_dist`. `latsize` controls how many unit cells are
plotted along each axis. `kwargs` are passed to `plot_bonds`. 
"""
function plot_all_bonds(crystal::Crystal, max_dist, latsize=(3,3,3); kwargs...)
    ref_bonds = reference_bonds(crystal, max_dist)
    interactions = QuadraticInteraction[]
    
    prev_dist = 0.0
    dist = 0
    class = 1
    for bond in ref_bonds
        # Exclude self (on-site) "bonds"
        if !(bond.i == bond.j && all(isequal(0), bond.n))
            if global_distance(crystal, bond) ≈ prev_dist
                class += 1
            else
                dist += 1
                class = 1
            end
            label = "J$(dist)_$(class)"
            push!(interactions, heisenberg(1.0, bond, label))
        end
    end
    @assert length(interactions) > 0 "No non-self interactions found!"

    plot_bonds(crystal, interactions, latsize; kwargs...)
end

"Plot all bonds between equivalent sites i and j"
function plot_all_bonds_between(crystal, i, j, max_dist, latsize=(3,3,3); kwargs...)
    ref_bonds = reference_bonds(crystal, max_dist)
    interactions = QuadraticInteraction[]

    prev_dist = 0.0
    dist = 0
    class = 1
    for bond in ref_bonds
        # Exclude self (on-site) "bonds"
        onsite = bond.i == bond.j && iszero(bond.n)
        target = bond.i == i && bond.j == j
        if !onsite && target
            if global_distance(crystal, bond) ≈ prev_dist
                class += 1
            else
                dist += 1
                class = 1
            end
            label = "J$(dist)_$(class)"
            push!(interactions, heisenberg(1.0, bond, label))
        end
    end
    @assert length(interactions) > 0 "No non-self interactions found!"

    plot_bonds(crystal, interactions, latsize; kwargs...)
end

"Plot the outlines of the unit cells of a lattice"
function plot_cells!(ax, sys::System; color=:grey, linewidth=1.0, kwargs...)
    lattice(i, j, k) = sys.crystal.latvecs * Vec3(i, j, k)

    pts = Vector{Makie.Point3f0}()
    nx, ny, nz = lattice.size
    for j in 1:ny
        for k in 1:nz
            bot_pt, top_pt = lattice(1, j, k), lattice(nx, j, k)
            push!(pts, Makie.Point3f0(bot_pt))
            push!(pts, Makie.Point3f0(top_pt))
        end
        for i in 1:nx
            left_pt, right_pt = lattice(i, j, 1), lattice(i, j, nz)
            push!(pts, Makie.Point3f0(left_pt))
            push!(pts, Makie.Point3f0(right_pt))
        end
    end
    for k in 1:nz
        for i in 1:nx
            left_pt, right_pt = lattice(i, 1, k), lattice(i, ny, k)
            push!(pts, Makie.Point3f0(left_pt))
            push!(pts, Makie.Point3f0(right_pt))
        end
    end

    Makie.linesegments!(ax, pts; color=color, linewidth=linewidth)
end
=#


function spin_vector_origins(sys::System, arrowlength)
    center = (sys.crystal.latvecs * Vec3(sys.latsize)) / 2
    return [global_position(sys,site) - sys.dipoles[site]*(arrowlength/2) - center for site in all_sites(sys)]
end

"""
    plot_spins(sys::System; linecolor=:grey, arrowcolor=:red, linewidth=0.1,
                                arrowsize=0.3, arrowlength=1.0, kwargs...)

Plot the spin configuration defined by `sys`. `kwargs` are passed to `Makie.arrows`.        
"""
function plot_spins(sys::System; linecolor=:grey, arrowcolor=:red,
    linewidth=0.1, arrowsize=0.2, arrowlength=0.2, show_axis=false, ortho=false, kwargs...)

    fig, ax = _setup_scene(; show_axis, ortho)

    pts = Makie.Point3f0.(spin_vector_origins(sys, arrowlength)[:])
    vecs = Makie.Vec3f0.(sys.dipoles[:])
    Makie.arrows!(
        ax, pts, vecs;
        linecolor, arrowcolor, linewidth, arrowsize,
        lengthscale=arrowlength, kwargs...
    )
    fig
end

"""
    anim_integration(sys, fname, steps_per_frame, Δt, nframes; kwargs...)

Produce an animation of constant-energy Landau-Lifshitz dynamics of the given `sys`.
# Arguments:
- `sys::System`: The spin system to integrate.
- `fname::String`: The path to save the animation to.
- `steps_per_frame::Int`: The number of integration steps to take per frame.
- `Δt::Float64`: The integration timestep size.
- `nframes::Int`: The number of frames to produce in the animation.

Other keyword arguments are passed to `Makie.arrows`.
"""
function anim_integration(
    sys::System, fname, steps_per_frame, Δt, nframes;
    linecolor=:grey, arrowcolor=:red, linewidth=0.1, arrowsize=0.2, arrowlength=0.2,
    kwargs...
)
    fig, ax = _setup_scene()

    pts = Makie.Point3f0.(spin_vector_origins(sys, arrowlength)[:])
    vecs = Makie.Observable(Makie.Vec3f0.(view(sys.dipoles,:)))
    Makie.arrows!(
        ax, pts, vecs;
        linecolor=linecolor, arrowcolor=arrowcolor, linewidth=linewidth, arrowsize=arrowsize,
        lengthscale=arrowlength, kwargs...    
    )
    display(fig)

    framerate = 30
    integrator = ImplicitMidpoint(Δt)

    Makie.record(fig, fname, 1:nframes; framerate=framerate) do frame
        for _ in 1:steps_per_frame
            step!(sys, integrator)
        end
        vecs[] = Makie.Vec3f0.(sys.dipoles[:])
    end
end

"""
    live_integration(sys, steps_per_frame, Δt; kwargs...)

Performs endless live constant-energy Landau-Lifshitz integration
in an interactive window.
"""
function live_integration(
    sys::System, steps_per_frame, Δt;
    linecolor=:grey, arrowcolor=:red, linewidth=0.1, arrowsize=0.2,
    arrowlength=0.2, framerate=30, kwargs...
)
    fig, ax = _setup_scene()

    pts = Makie.Point3f0.(spin_vector_origins(sys, arrowlength)[:])
    vecs = Makie.Observable(Makie.Vec3f0.(view(sys.dipoles,:)))
    Makie.arrows!(
        ax, pts, vecs;
        linecolor=linecolor, arrowcolor=arrowcolor, linewidth=linewidth, arrowsize=arrowsize,
        lengthscale=arrowlength, kwargs...    
    )
    display(fig)

    integrator = ImplicitMidpoint(Δt)

    while true
        for step in 1:steps_per_frame
            step!(sys, integrator)
        end
        vecs[] = Makie.Vec3f0.(sys.dipoles[:])
        sleep(1/framerate)
    end
end

"""
    live_langevin_integration(sys, steps_per_frame, Δt, kT; λ=0.1, kwargs...)

Performs endless live Langevin Landau-Lifshitz integration
in an interactive window.
"""
function live_langevin_integration(
    sys::System, steps_per_frame, Δt, kT;
    linecolor=:grey, arrowcolor=:red, linewidth=0.1, arrowsize=0.2,
    arrowlength=0.2, λ=0.1, framerate=30, kwargs...
)
    fig, ax = _setup_scene(; show_axis=false)
    pts = Makie.Point3f0.(spin_vector_origins(sys, arrowlength)[:])
    vecs = Makie.Observable(Makie.Vec3f0.(view(sys.dipoles,:)))
    
    Makie.arrows!(
        ax, pts, vecs;
        linecolor=linecolor, arrowcolor=arrowcolor, linewidth=linewidth, arrowsize=arrowsize,
        lengthscale=arrowlength, kwargs...    
    )
    display(fig)

    integrator = Langevin(Δt; kT, λ)

    while true
        for _ in 1:steps_per_frame
            step!(sys, integrator)
        end
        vecs[] = Makie.Vec3f0.(sys.dipoles[:])
        sleep(1/framerate)
    end
end

"Plots slices of a 3D structure factor. Input array should have shape [3, Lx, Ly, Lz, T]"
function plot_3d_structure_factor(sfactor::Array{Float64, 5}, iz)
    fig, ax = _setup_scene(; show_axis=true)

    Sdim, Lx, Ly, Lz, T = size(sfactor)
    # Average over Sxx, Syy, Szz - in future give controls to user
    sfactor = dropdims(sum(sfactor, dims=1) ./ 3, dims=1)
    # Index out the asked-for slice - in future give controls to user
    sfactor = sfactor[:, :, iz, :]

    # Nearest-neighbor upsample this to a similar size as the T axis.
    sampx, sampy = div(T, 2Lx), div(T, 2Ly)
    sfactor = repeat(sfactor, inner=(sampx, sampy, 1))

    kx = 1:sampx*Lx
    ky = 1:sampy*Ly
    ω  = 1:T

    lsgrid = Makie.labelslidergrid!(
        fig,
        ["kx", "ky", "ω"],
        [1:sampx*Lx, 1:sampy*Ly, 1:T]
    )
    fig[2, 1] = lsgrid.layout
    volslices = Makie.volumeslices!(ax, kx, ky, ω, sfactor)

    # See: http://makie.juliaplots.org/stable/plotting_functions/volumeslices.html
    sl_yz, sl_xz, sl_xy = lsgrid.sliders
    Makie.on(sl_yz.value) do v; volslices[:update_yz][](v) end
    Makie.on(sl_xz.value) do v; volslices[:update_xz][](v) end
    Makie.on(sl_xy.value) do v; volslices[:update_xy][](v) end

    Makie.set_close_to!(sl_yz, .5Lx)
    Makie.set_close_to!(sl_xz, .5Ly)
    Makie.set_close_to!(sl_xy, .5T)

    fig
end
