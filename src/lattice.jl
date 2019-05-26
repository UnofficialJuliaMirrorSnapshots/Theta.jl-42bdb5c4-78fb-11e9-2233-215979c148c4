mutable struct Lattice
    n::Int64 # number of rows in basis matrix
    m::Int64 # number of columns in basis matrix
    basis::Array{Float64} # matrix whose columns form basis of lattice
    μ::Array{Float64} # lower triangular matrix of gram-schmidt coefficients
    r::Array{Float64} # squared norm of gram-schmidt basis vectors
    gs::Array{Float64} # columns are gram-schmidt basis vectors

    """
        Lattice(basis)

    Construct a Lattice generated by the input basis matrix.
    """
    Lattice(basis) = gram_schmidt(basis);
    Lattice(n, m, basis, μ, r, gs) = new(n, m, basis, μ, r, gs);
end

"""
    gram_schmidt(M)

Compute Gram-Schmidt orthogonalization on columns of input matrix.
"""
function gram_schmidt(M::Array{<:Real})
    n = size(M, 1); # number of rows of matrix
    m = size(M, 2); # number of columns of matrix
    μ = zeros(Float64,m,m); # lower triangular matrix of gram-schmidt coefficients
    r = zeros(Float64,m); # squared norm of gram-schmidt basis vectors
    gs = zeros(Float64,n,m); # columns are gram-schmidt basis vectors
    for i = 1:m
        b = M[:,i];
        for j = 1:i-1 # compute gram-schmidt coefficients for j < i
            μ[i,j] = (transpose(b)*gs[:,j])/r[j];
        end
        for j = 1:i-1 # compute i-th gram-schmidt basis vector
            b -= μ[i,j]*gs[:,j];
        end
        gs[:,i] = b;
        r[i] = norm(b)^2; # squared norm of gram-schmidt vector
        μ[i,i] = (transpose(b)*M[:,i])/r[i];
    end
    return Lattice(n, m, M, μ, r, gs);
end

"""
    update_gram_schmidt!(L)

Update Gram-Schmidt coefficients and vectors.
"""
function update_gram_schmidt!(L::Lattice)
    for i = 1:L.m
        b = L.basis[:,i];
        for j = 1:i-1 # compute gram-schmidt coefficients for j < i
            L.μ[i,j] = (transpose(b)*L.gs[:,j])/L.r[j];
        end
        for j = 1:i-1 # compute i-th gram-schmidt basis vector
            b -= L.μ[i,j]*L.gs[:,j];
        end
        L.gs[:,i] = b;
        L.r[i] = norm(b)^2; # squared norm of gram-schmidt vector
        L.μ[i,i] = (transpose(b)*L.basis[:,i])/L.r[i];
    end
    return L;
end


"""
    size_reduce(L)

Compute size reduction of basis vectors of lattice, such that all Gram-Schmidt coefficients have absolute value at most 1/2. Modify the Gram-Schmidt coefficients of input lattice accordingly.
"""
function size_reduce!(L::Lattice)
    for i =2:L.m
        for j = i-1:-1:1
            L.basis[:,i] -= round(L.μ[i,j])*L.basis[:,j];
            for k = 1:j
                L.μ[i,k] -= round(L.μ[i,j])*L.μ[j,k];
            end
        end
    end
    return L
end

"""
    check_size_reduce(L, tol=1e-5)

Check whether basis vectors of input lattice are size-reduced.
"""
function check_size_reduce(L::Lattice, tol::Real=1e-5)
    for i = 1:L.m, j = 1:i-1
        if abs(L.μ[i,j]) > 0.5 + tol
            return false
        end
    end
    return true
end

"""
    lll!(L, δ=0.75)

Compute LLL reduction of input lattice, with parameter δ such that ``0.25 < δ < 1``.
"""
function lll!(L::Lattice, δ::Real=0.75)
    k = 2;
    while k <= L.m
        size_reduce!(L);
        if norm(L.gs[:,k])^2 >= (δ - L.μ[k,k-1]^2)*norm(L.gs[:,k-1])^2
            k += 1;
        else
            b = copy(L.basis[:,k]);
            L.basis[:,k] = copy(L.basis[:,k-1]);
            L.basis[:,k-1] = b;
            update_gram_schmidt!(L);
            k = max(2, k-1);
        end
    end
    return L;
end


"""
    lll(M, δ=0.75)

Compute LLL reduction of input matrix, with parameter δ such that ``0.25 < δ < 1``.
"""
function lll(M::Array{<:Real}, δ::Real=0.75)
    return lll(Lattice(M)).basis;
end

"""
    check_lll(L, δ=0.75)

Check whether input lattice has an LLL-reduced basis, with parameter δ such that ``0.25 < δ < 1``.
"""
function check_lll(L::Lattice, δ::Real=0.75)
    if !check_size_reduce(L)
        return false;
    end
    for i=1:L.m-1
        if L.r[i+1] < (δ-L.μ[i+1,i]^2)*L.r[i]
            return false;
        end
    end
    return true;
end

"""
    svp(M)

Compute shortest vector in lattice generated by M, using Schnorr-Euchner enumeration.
"""
function svp(M::Array{<:Real})
    L = Lattice(M);
    x = zeros(Int64, L.m);
    x[L.m] = 1;
    A = norm(M[:,L.m])^2
    sol, length =  enum_svp(L, x, L.m, A, 0.0);
    vect = sum([sol[j]*L.basis[:,j] for j=1:L.m]);
    return [vect, length, sol];
end


"""
    enum_svp(L, x, i, radius, l)

Enumerate all lattice points in subtree at height i, where parent nodes are defined by x. Helper method for [`svp`](@ref).
"""
function enum_svp(L::Lattice, x::Array{<:Integer}, i::Integer, radius::Real, l::Real)
    sol = copy(x);
    c = -sum(Float64[x[j]*L.μ[j,i] for j=i+1:L.m]);
    interval = sqrt((radius-l)/L.r[i]); # interval of possibilities for x[i]
    k = floor(Int64, c); # stores value of x[i]
    Δk = 0; # used to do search in zig-zag path
    Δ²k = -1; # used to do search in zig-zag path
    lbound = floor(Int64, c - interval);
    ubound = ceil(Int64, c + interval);
    while k>= lbound & k <= ubound
        l_new = l + (k-c)^2*L.r[i];
        if l_new <= radius # possible new solution found
            if i == 1 & ~(l_new == 0) # leaf of enumeration tree
                # l_new is approximation of length of new solution. Do exact computation of length to avoid errors
                old_sol = sol[i];
                sol[i] = k;
                new_length = norm(sum([sol[j]*L.basis[:,j] for j=1:L.m]))^2;
                if radius > new_length # prune enumeration tree
                    radius = new_length;
                else
                    sol[i] = old_sol;
                end
            elseif i > 1 # solve subtree enumeration recursively
                old_sol = sol[i];
                sol[i] = k;
                subtree_sol, subtree_length = enum_svp(L, sol, i-1, radius, l_new);
                if subtree_length < radius
                    sol[1:i-1] = subtree_sol[1:i-1];
                    radius = subtree_length;
                else
                    sol[i] = old_sol;
                end
            end
        end
        Δ²k = - Δ²k;
        Δk = Δ²k - Δk;
        k += Δk;
    end
    return [sol, radius];
end
