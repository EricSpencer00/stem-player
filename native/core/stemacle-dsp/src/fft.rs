//! In-place radix-2 FFT, a direct port of `fftIP`/`ifftIP` in `app/index.html`.
//!
//! Kept byte-faithful to the web gold master so spectrogram magnitudes match
//! within floating-point tolerance. Length must be a power of two.

/// In-place complex FFT. Mirrors the JS iterative Cooley-Tukey with the same
/// bit-reversal permutation and twiddle recurrence.
pub fn fft_ip(re: &mut [f32], im: &mut [f32]) {
    let n = re.len();
    debug_assert_eq!(n, im.len());
    debug_assert!(n.is_power_of_two(), "fft length must be a power of two");

    // bit-reversal permutation (matches the JS `for(i=1,j=0; ...)` loop)
    let mut j = 0usize;
    for i in 1..n {
        let mut bit = n >> 1;
        while j & bit != 0 {
            j ^= bit;
            bit >>= 1;
        }
        j ^= bit;
        if i < j {
            re.swap(i, j);
            im.swap(i, j);
        }
    }

    let mut len = 2usize;
    while len <= n {
        let ang = -2.0 * std::f32::consts::PI / len as f32;
        let (wr0, wi0) = (ang.cos(), ang.sin());
        let half = len >> 1;
        let mut i = 0usize;
        while i < n {
            let mut wr = 1.0f32;
            let mut wi = 0.0f32;
            for k in 0..half {
                let u = i + k;
                let v = u + half;
                let t_re = wr * re[v] - wi * im[v];
                let t_im = wr * im[v] + wi * re[v];
                re[v] = re[u] - t_re;
                im[v] = im[u] - t_im;
                re[u] += t_re;
                im[u] += t_im;
                let nr = wr * wr0 - wi * wi0;
                wi = wr * wi0 + wi * wr0;
                wr = nr;
            }
            i += len;
        }
        len <<= 1;
    }
}

/// In-place inverse FFT. Mirrors `ifftIP`: conjugate, forward FFT, scale, conjugate.
pub fn ifft_ip(re: &mut [f32], im: &mut [f32]) {
    for v in im.iter_mut() {
        *v = -*v;
    }
    fft_ip(re, im);
    let n = re.len() as f32;
    for i in 0..re.len() {
        re[i] /= n;
        im[i] = -im[i] / n;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Naive O(n^2) DFT used as ground truth for the FFT.
    fn naive_dft(re: &[f32], im: &[f32]) -> (Vec<f32>, Vec<f32>) {
        let n = re.len();
        let mut out_re = vec![0.0f32; n];
        let mut out_im = vec![0.0f32; n];
        for k in 0..n {
            let mut sr = 0.0f64;
            let mut si = 0.0f64;
            for t in 0..n {
                let ang = -2.0 * std::f64::consts::PI * (k as f64) * (t as f64) / n as f64;
                let (c, s) = (ang.cos(), ang.sin());
                sr += re[t] as f64 * c - im[t] as f64 * s;
                si += re[t] as f64 * s + im[t] as f64 * c;
            }
            out_re[k] = sr as f32;
            out_im[k] = si as f32;
        }
        (out_re, out_im)
    }

    #[test]
    fn fft_matches_naive_dft() {
        let n = 256;
        let mut re: Vec<f32> = (0..n)
            .map(|i| (0.013 * i as f32).sin() + 0.5 * (0.21 * i as f32).cos())
            .collect();
        let mut im = vec![0.0f32; n];
        let (er, ei) = naive_dft(&re, &im);
        fft_ip(&mut re, &mut im);
        for k in 0..n {
            assert!((re[k] - er[k]).abs() < 1e-2, "re[{k}] {} vs {}", re[k], er[k]);
            assert!((im[k] - ei[k]).abs() < 1e-2, "im[{k}] {} vs {}", im[k], ei[k]);
        }
    }

    #[test]
    fn fft_then_ifft_reconstructs() {
        let n = 1024;
        let orig: Vec<f32> = (0..n).map(|i| (0.037 * i as f32).sin()).collect();
        let mut re = orig.clone();
        let mut im = vec![0.0f32; n];
        fft_ip(&mut re, &mut im);
        ifft_ip(&mut re, &mut im);
        for i in 0..n {
            assert!((re[i] - orig[i]).abs() < 1e-4, "sample {i}: {} vs {}", re[i], orig[i]);
            assert!(im[i].abs() < 1e-4, "residual imag at {i}: {}", im[i]);
        }
    }
}
