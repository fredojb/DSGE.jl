using DSGE
using HDF5

# Test in model optimization
model = Model990()
model.testing=true

x0 = h5open(inpath(model, "user", "paramsstart.h5")) do file
    read(file, "params")
end
data = h5open(inpath(model, "data", "data_REF.h5")) do file
    read(file, "data")
end
file = h5open("$path/../reference/csminwel_out.h5","r")
minimum_ = read(file, "minimum")
f_minimum = read(file, "f_minimum")
H_expected = read(file, "H")
close(file)

# See src/estimate/estimate.jl
update!(model, x0)
n_iterations = 3

@time out, H = optimize!(model, data; iterations=n_iterations)

@test_matrix_approx_eq minimum_ out.minimum
@test_approx_eq f_minimum out.f_minimum
@test_matrix_approx_eq H_expected H

nothing
