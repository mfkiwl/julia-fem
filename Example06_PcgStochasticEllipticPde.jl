push!(LOAD_PATH, "./Fem/")
import Pkg
Pkg.activate(".")
using Fem
using NPZ
using IterativeSolvers
using Preconditioners

model = "SExp"
sig2 = 1.
L = .1
tentative_nnode = 400_000
load_existing_mesh = true

root_fname = get_root_filename(model, sig2, L, tentative_nnode)

if load_existing_mesh
  cells, points, point_markers, cell_neighbors = load_mesh(tentative_nnode)
else
  mesh = get_mesh(tentative_nnode)
  cells = mesh.cell
  points = mesh.point
  point_markers = mesh.point_marker
  cell_neighbors = mesh.cell_neighbor
end

dirichlet_inds_g2l, not_dirichlet_inds_g2l,
dirichlet_inds_l2g, not_dirichlet_inds_l2g = 
get_dirichlet_inds(points, point_markers)

function f(x::Float64, y::Float64)
  return -1.
end
  
function uexact(xx::Float64, yy::Float64)
  return .734
end

println("nnode = $(size(points)[2])")
println("nel = $(size(cells)[2])")

M = get_mass_matrix(cells, points)
Λ = npzread("data/$root_fname.kl-eigvals.npz")
Ψ = npzread("data/$root_fname.kl-eigvecs.npz")
g = npzread("data/$root_fname.kl-eigvecs.npz")
ξ, g = draw(Λ, Ψ)

# The eigenfunctions obtained by domain 
# decomposition are not perfectly orthogonal
χ = get_kl_coordinates(g, Λ, Ψ, M)  
println("extrema(ξ - χ) = $(extrema(ξ - χ))")

print("in-place draw ...")
@time draw!(Λ, Ψ, ξ, g)

print("do_isotropic_elliptic_assembly ...")
A, b = @time do_isotropic_elliptic_assembly(cells, points,
                                            dirichlet_inds_g2l,
                                            not_dirichlet_inds_g2l,
                                            point_markers,
                                            exp.(g), f, uexact)

print("assemble amg preconditioner ...")
Π1 = @time AMGPreconditioner{SmoothedAggregation}(A);

print("solve for u_no_dirichlet ...")
u_no_dirichlet = @time IterativeSolvers.cg(A, b, Pl=Π1)

draw!(Λ, Ψ, ξ, g)
Π2 = @time AMGPreconditioner{SmoothedAggregation}(A);