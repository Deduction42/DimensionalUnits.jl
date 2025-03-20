const FAST_RATIONAL = FixedRational{DEFAULT_NUMERATOR_TYPE,DEFAULT_DENOM}
const DEFAULT_USYMBOL = :_

abstract type AbstractUnitLike end
abstract type AbstractDimensions{P} <: AbstractUnitLike end
abstract type AbstractUnits{D<:AbstractDimensions} <: AbstractUnitLike end
abstract type AbstractAffineUnits{D<:AbstractDimensions} <: AbstractUnits{D} end 

Base.@pure static_fieldnames(t::Type) = Base.fieldnames(t)

@kwdef struct Dimensions{P} <: AbstractDimensions{P}
    length::P = 0
    mass::P = 0
    time::P = 0
    current::P = 0
    temperature::P = 0
    luminosity::P = 0
    amount::P = 0
end

Dimensions(args...) = Dimensions{FAST_RATIONAL}(args...)
Dimensions(;kwargs...) = Dimensions{FAST_RATIONAL}(;kwargs...)
Dimensions(d::Dimensions) = d
DEFAULT_DIMENSONS = Dimensions{FAST_RATIONAL}

uscale(u::AbstractDimensions) = 1 # All AbstractDimensions have unity scale
uoffset(u::AbstractDimensions) = 0 # All AbstractDimensions have no offset
dimension(u::AbstractDimensions) = u
usymbol(u::AbstractDimensions) = DEFAULT_USYMBOL
Base.getindex(d::AbstractDimensions, k::Symbol) = getproperty(d, k)
dimtype(::Type{<:AbstractUnits{D}}) where D = D
dimtype(::Type{D}) where D<:AbstractDimensions = D

function unit_symbols(::Type{<:Dimensions})
    return Dimensions{Symbol}(
        length=:m, mass=:kg, time=:s, current=:A, temperature=:K, luminosity=:cd, amount=:mol
    )
end

"""
    NoDims{P}

A unitless dimension, compatible with any other dimension

Calling `getproperty` will always return `zero(P)`
promote(Type{<:NoDims}, D<:AbstractDimension) will return D 
convert(Type{D}, NoDims) where D<:AbstractDimensions will return D()
"""
struct NoDims{P} <: AbstractDimensions{P} end
NoDims() = NoDims{FAST_RATIONAL}()
Base.getproperty(::NoDims{P}, ::Symbol) where {P} = zero(P)
unit_symbols(::Type{<:NoDims}) = NoDims{Symbol}()


"""
    dimension_names(::Type{<:AbstractDimensions})

Overloadable feieldnames for a dimension (returns a tuple of the dimensions field names)
This should be static so that it can be hardcoded during compilation. 
Can use this to overload the default "fieldnames" behaviour
"""
@inline function dimension_names(::Type{D}) where {D<:AbstractDimensions}
    return static_fieldnames(D)
end


@kwdef struct AffineUnits{D<:AbstractDimensions} <: AbstractAffineUnits{D}
    scale::Float64 = 1
    offset::Float64 = 0
    dims::D
    symbol::Symbol=DEFAULT_USYMBOL 
end

AffineUnits(scale, offset, dims::D, symbol=DEFAULT_USYMBOL) where {D<:AbstractDimensions} = AffineUnits{D}(scale, offset, dims, symbol)
AffineUnits(u::AffineUnits) = u

uscale(u::AffineUnits) = u.scale
uoffset(u::AffineUnits) = u.offset 
dimension(u::AffineUnits) = u.dims 
usymbol(u::AffineUnits) = u.symbol
remove_offset(u::U) where U<:AbstractAffineUnits = constructorof(U)(scale=uscale(u), offset=0, dims=dimension(u))

#=================================================================================================
Quantity types
The basic type is Quantity, which belongs to <:Any (hence it has no real hierarchy)
Other types are "narrower" in order to slot into different parts of the number hierarchy
=================================================================================================#

struct Quantity{T<:Any,U<:AbstractUnitLike}
    value :: T
    units :: U 
end
narrowest_quantity(::Type{<:Any}) = Quantity

struct NumberQuantity{T<:Number,U<:AbstractUnitLike} <: Number
    value :: T
    units :: U 
end
narrowest_quantity(::Type{<:Number}) = NumberQuantity

struct RealQuantity{T<:Real,U<:AbstractUnitLike} <: Real
    value :: T
    units :: U 
end
narrowest_quantity(::Type{<:Real}) = RealQuantity

narrowest_quantity(x::Any) = narrowest_quantity(typeof(x))

const UnionQuantity{T,U} = Union{Quantity{T,U}, NumberQuantity{T,U}, RealQuantity{T,U}}
#const UnionNumberOrQuantity = Union{Number, UnionQuantity}

ustrip(q::UnionQuantity) = q.value
unit(q::UnionQuantity) = q.units
dimension(q::UnionQuantity) = dimension(unit(q))

Quantity(q::UnionQuantity) = Quantity(ustrip(q), unit(q))
Quantity{T,U}(q::UnionQuantity) where {T,U} = Quantity{T,U}(ustrip(q), unit(q))

NumberQuantity(q::UnionQuantity) = NumberQuantity(ustrip(q), unit(q))
NumberQuantity{T,U}(q::UnionQuantity) where {T,U} = NumberQuantity{T,U}(ustrip(q), unit(q))

RealQuantity(q::UnionQuantity) = RealQuantity(ustrip(q), unit(q))
RealQuantity{T,U}(q::UnionQuantity) where {T,U} = RealQuantity{T,U}(ustrip(q), unit(q))



"""
    quantity(x, u::AbstractUnitLike)

Constructs a quantity based on the narrowest quantity type that accepts x as an agument
"""
quantity(x, u::AbstractUnitLike) = narrowest_quantity(x)(x, u)

"""
    narrowest(q::UnionQuantity)

Returns the narrowest quantity type of `q`
"""
narrowest(q::UnionQuantity) = quantity(ustrip(q), unit(q))
widest(q::UnionQuantity) = Quantity(ustrip(q), unit(q))

"""
    constructorof(::Type{T}) where T = Base.typename(T).wrapper

Return the constructor of a type T{PS...} by default it only returns T (i.e. removes type parameters)
This function can be overloaded if custom behaviour is needed
"""
constructorof(::Type{T}) where T = Base.typename(T).wrapper
constructorof(::Type{<:Dimensions})  = Dimensions
constructorof(::Type{<:AffineUnits}) = AffineUnits
constructorof(::Type{<:Quantity}) = Quantity
constructorof(::Type{<:RealQuantity}) = RealQuantity
constructorof(::Type{<:NumberQuantity}) = NumberQuantity

#=============================================================================================
Errors and assertion functions
=============================================================================================#

"""
    DimensionError{D} <: Exception

Error thrown when an operation is dimensionally invalid given the arguments
"""
struct DimensionError{Q1,Q2} <: Exception
    q1::Q1
    q2::Q2
    DimensionError(q1::Q1, q2::Q2) where {Q1,Q2} = new{Q1,Q2}(q1, q2)
    DimensionError(q1) = DimensionError(q1, nothing)
end
Base.showerror(io::IO, e::DimensionError) = print(io, "DimensionError: ", e.q1, " and ", e.q2, " have incompatible dimensions")
Base.showerror(io::IO, e::DimensionError{<:Any,Nothing}) = print(io, "DimensionError: ", e.q1, " is not dimensionless")

"""
    NotScalarError{D} <: Exception

Error thrown for non-scalar units when the operation is only valid for scalar units
"""
struct NotScalarError{D} <: Exception
    dim::D
    NotScalarError(dim) = new{typeof(dim)}(dim)
end
Base.showerror(io::IO, e::NotScalarError) = print(io, "NotScalarError: ", e.dim, " cannot be treated as scalar, operation only valid for scalar units")


"""
    NotDimensionError{D} <: Exception

Error thrown for non-dimensional units (scaled or affine) when the operation is only valid for dimensional units
"""
struct NotDimensionError{D} <: Exception
    dim::D
    NotDimensionError(dim) = new{typeof(dim)}(dim)
end
Base.showerror(io::IO, e::NotDimensionError) = print(io, "NotDimensionError: ", e.dim, " cannot be treated as dimension, operation only valid for dimension units")


assert_scalar(u::AbstractDimensions)  = u
assert_scalar(u::AbstractAffineUnits) = iszero(uoffset(u)) ? u : throw(NotScalarError(u))
scalar_dimension(u::AbstractUnitLike) = dimension(assert_scalar(u))

assert_dimension(u::AbstractDimensions) =  u
assert_dimension(u::AbstractAffineUnits) = isone(uscale(u)) & iszero(uoffset(u)) ? u : throw(NotDimensionError(u))

assert_dimensionless(u::AbstractUnitLike) = isdimensionless(u) ? u : DimensionError(u)
assert_dimensionless(q::UnionQuantity) = isdimensionless(unit(q)) ? q : DimensionError(q)

function isdimensionless(u::U) where U<:AbstractDimensions
    zero_dimension(obj::AbstractDimensions, fn::Symbol) = iszero(getproperty(obj, fn))
    return all(Base.Fix1(zero_dimension, u), dimension_names(U)) 
end
isdimensionless(u::AbstractUnitLike) = isdimensionless(dimension(u))