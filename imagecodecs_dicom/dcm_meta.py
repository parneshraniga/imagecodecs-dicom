from dataclasses import dataclass

@dataclass
class DCMPixelMeta:

    samples_per_pixel : int
    photometric_interpretation: str
    rows: int
    columns : int
    bits_allocated : int
    bits_stored : int
    high_bit : int
    pixel_representation : int
    planar_configuration : int
    pixel_data_format: str ## float and double datasets are only native
