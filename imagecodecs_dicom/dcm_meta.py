from dataclasses import dataclass
from typing import Optional

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
    transfer_syntax_uid : Optional[str]

def get_tsu_from_image_jpeg(is_lossless, is_baseline, predictor_selection_value) -> str:

    if not is_lossless:
        if predictor_selection_value == 1:
            return "1.2.840.10008.1.2.4.70"
        else:
            return "1.2.840.10008.1.2.4.57"
    else:
        if is_baseline:
            return "1.2.840.10008.1.2.4.50"
        else:
            return "1.2.840.10008.1.2.4.51"



