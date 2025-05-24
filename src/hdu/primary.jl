####    Primary HDU functions

struct ImageField <: AbstractField
    type::Type
    zero::Real
    scale::Real
    miss::Union{Integer, Nothing}
    dmin::Union{AbstractFloat, Nothing}
    dmax::Union{AbstractFloat, Nothing}
end

function read(io::IO, ::Type{Primary}, format::DataFormat,
    fields::ImageField; scale=true, kwds...)

    begpos = position(io)
    #  Read data array
    M, N = sizeof(format.type), format.leng
    if N > 0
        data = read(io, format, fields)
        #  Seek to end of the last data block
        seek(io, begpos + BLOCKLEN*div(M*N, BLOCKLEN, RoundUp))

        data = scale ? fields.zero .+ fields.scale.*data : data
        #=
        if get(kwds, :unit, true)
            data = apply_unit(data, fields)
        end
        =#
    else
        data = nothing
    end

    ####    Get WCS keywords
    data
end

function write(io::IO, ::Type{Primary}, data::Nothing, format::DataFormat,
    fields::ImageField; kwds...)
end

function write(io::IO, ::Type{Primary}, data::AbstractArray,
    format::DataFormat, fields::ImageField; kwds...)

    if format.leng > 0
        # data = remove_units(data)

        write(io, data, fields; kwds...)
        padblock(io, format)
    end
end

function verify!(::Type{Primary}, cards::Cards, format::DataFormat,
    mankeys::D) where D<:Dict{AbstractString, ValueType}

    if !get(mankeys, "SIMPLE", true)
        println("Warning: Primary HDU is nonconformant.")
    end
    if haskey(mankeys, "BITPIX") && format.type != BITS2TYPE[mankeys["BITPIX"]]
        setindex!(cards, TYPE2BITS[format.type], "BITPIX")
        println("Warning: BITPIX set to $(TYPE2BITS[format.type])).")
    end
    if haskey(mankeys, "NAXIS1") && format.shape != datasize(cards, 1)
        N = length(format.shape)
        setindex!(cards, N, "NAXIS")
        for j=1:N setindex!(cards, format.shape[j], "NAXIS$j") end
        println("Warning: NAXIS$(1:N) set to $(format.shape)")
    end
    cards
end

function DataFormat(::Type{Primary}, data::Nothing, mankeys::Dict{S, V}) where
    {S<:AbstractString, V<:ValueType}

    #  Determine format from data
    type  = BITS2TYPE[get(mankeys, "BITPIX", 32)]
    leng  = datalength(mankeys, 1)
    shape = datasize(mankeys, 1)
    param = get(mankeys, "PCOUNT", 0)
    group = get(mankeys, "GCOUNT", 1)
    heap  = param > 0 ? get(mankeys, "THEAP", 0) : 0
    DataFormat(type, leng, shape, param, group, heap)
end

function FieldFormat(::Type{Primary}, format::DataFormat, reskeys::Dict{S, V},
    data::Nothing) where {S<:AbstractString, V<:ValueType}

    #  Get missing value
    zero_ = get(reskeys, "BZERO", zero(format.type))
    scale = get(reskeys, "BSCALE", one(format.type))
    miss  = format.type in MISSTYPE ? get(reskeys, "BLANK", nothing) : nothing
    dmin  = get(reskeys, "DATAMIN", nothing)
    dmax  = get(reskeys, "DATAMAX", nothing)
    ImageField(format.type, zero_, scale, miss, dmin, dmax)
end

function DataFormat(::Type{Primary}, data::AbstractArray,
    mankeys::Dict{S, V}) where {S<:AbstractString, V<:ValueType}

    #  Determine format from data
    type  = eltype(data)
    leng  = length(data)
    shape = size(data)
    param = get(mankeys, "PCOUNT", 0)
    group = get(mankeys, "GCOUNT", 1)
    heap = 0
    DataFormat(type, leng, shape, param, group, heap)
end

function FieldFormat(::Type{Primary}, format::DataFormat, reskeys::Dict{S, V},
    data::AbstractArray) where {S<:AbstractString, V<:ValueType}

    #  Get missing value
    zero_ = get(reskeys, "BZERO", zero(format.type))
    scale = get(reskeys, "BSCALE", one(format.type))
    miss  = format.type in MISSTYPE ? get(reskeys, "BLANK", nothing) : nothing
    dmin  = get(reskeys, "DATAMIN", nothing)
    dmax  = get(reskeys, "DATAMAX", nothing)
    ImageField(format.type, zero_, scale, miss, dmin, dmax)
end

function create_cards!(::Type{Primary}, format::DataFormat, fields::ImageField,
    cards::Cards; kwds...)

    N, B = length(format.shape), TYPE2BITS[format.type]
    #  Create mandatory (required) header cards and remove them from the deck
    #  if necessary
    required = Vector{Card{<:Any}}(undef, 3+N)
    required[1] = popat!(cards, "SIMPLE", Card("SIMPLE", true))
    required[2] = popat!(cards, "BITPIX", Card("BITPIX", B))
    required[3] = popat!(cards, "NAXIS", Card("NAXIS", N))
    required[4:3+N] .= [popat!(cards, "NAXIS$j",
        Card("NAXIS$j", format.shape[j])) for j = 1:N]

    #  Append remaining cards in deck, but first remove the END card
    popat!(cards, "END")
    M = length(cards)
    kards = Vector{Card{<:Any}}(undef, 3+N+M)
    kards[1:3+N] .= required
    kards[4+N:3+N+M] .= cards
    #  END card is implied. It will be appended on write.
    kards
end

function create_data(::Type{Primary}, format::DataFormat, ::ImageField;
    kwds...)
    #  Create simple N-dimensional array of zeros of type BITPIX
    length(format.shape) > 0 ? zeros(format.type, format.shape) : nothing
end

function read(io::IO, format::DataFormat, fields::ImageField)

    M, N, shape = sizeof(format.type), format.leng, format.shape
    #  Or preallocate array and use read!
    data = reshape(ntoh.(
        reinterpret(format.type, Base.read(io, M*N))), shape)
    #  Assign missing values
    if !isnothing(fields.miss)
        data[data .== fields.miss] .= missing
    end
    data
end

function write(io::IO, data::AbstractArray, fields::ImageField)
    #  Assign missing values
    if !isnothing(fields.miss)
        data[data .== missing] .= fields.miss
    end
    n = Base.write(io, hton.(reshape(data, :)))
end

function apply_units(data::AbstractArray, fields::ImageField)
    !isnothing(fields.unit) ? data*fields.unit : data
end

function remove_units(data::AbstractArray)
    typeof(data) <: Quantity ? data.val : data
end
