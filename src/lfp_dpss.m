function [tapers, eigenvalues] = lfp_dpss(nSamples, nw, taperCount)
%LFP_DPSS Return discrete prolate spheroidal sequences without Python.
%   Uses MATLAB's dpss when available.  Otherwise the standard symmetric
%   tridiagonal DPSS eigenproblem is solved with base-MATLAB eig/eigs.

arguments
    nSamples (1,1) double {mustBeInteger, mustBeGreaterThanOrEqual(nSamples, 2)}
    nw (1,1) double {mustBeFinite, mustBeGreaterThan(nw, 0.5)}
    taperCount (1,1) double {mustBeInteger, mustBePositive} = max(1, floor(2 * nw) - 1)
end

if nw >= nSamples / 2
    error('LFP:InvalidDPSS', 'NW must be smaller than N/2 for a DPSS sequence.');
end
defaultCount = max(1, floor(2 * nw) - 1);
taperCount = min(max(1, taperCount), nSamples);
if taperCount > defaultCount * 2
    warning('LFP:LargeDPSSCount', 'Taper count exceeds the usual floor(2*NW)-1 recommendation.');
end

if exist('dpss', 'file') == 2 && nargin('dpss') >= 3
    [tapers, eigenvalues] = dpss(nSamples, nw, taperCount);
    tapers = double(tapers);
    eigenvalues = double(eigenvalues(:));
    return;
end

% Percival & Walden tridiagonal formulation.  Its eigenvectors are the
% same DPSS tapers as the dense concentration matrix but avoid an O(N^2)
% matrix allocation for typical LFP windows.
n = (0:nSamples - 1)';
diagonal = ((nSamples - 1 - 2 * n) / 2) .^ 2 .* cos(2 * pi * nw / nSamples);
offDiagonal = (n(1:end-1) + 1) .* (nSamples - 1 - n(1:end-1)) / 2;
tri = spdiags([[offDiagonal; 0], diagonal, [0; offDiagonal]], -1:1, nSamples, nSamples);
try
    if nSamples <= 4096
        [vectors, values] = eig(full(tri), 'vector');
    else
        [vectors, values] = eigs(tri, taperCount, 'largestreal');
        values = diag(values);
    end
catch exception
    error('LFP:DPSSUnavailable', 'Base-MATLAB DPSS eigensolver failed: %s', exception.message);
end
[eigenvalues, order] = sort(real(values(:)), 'descend');
order = order(1:taperCount);
tapers = real(vectors(:, order));
tapers = tapers ./ max(sqrt(sum(tapers .^ 2, 1)), eps);
eigenvalues = eigenvalues(1:taperCount);
end
