function vidStruct = parseMovieSyncs(mffFolder)

% Author: Mika Hess, Modified by: James Barlow
% Created: 07/24/2026
% Last updated: 10/18/2026

% Reads movieSyncs1.xml from an .mff into a per-video timing table

% IN:   mffFolder = path to the .mff folder

% OUT:  vidStruct = struct array, one element per video segment
%           fileName = video file name
%           eegBeginSec / eegEndSec = segment span on the EEG clock (s; xml stores microseconds)
%           videoBeginSec / videoEndSec = same span on the video's own clock (s)
arguments
    mffFolder {mustBeTextScalar}
end

findMovie = fullfile(mffFolder, 'movieSyncs1.xml');
if ~isfile(findMovie), error('Movie sync file missing from .mff, please ensure folder containing raw EEG data contains movieSyncs1.xml'); end
domNodes = xmlread(findMovie);
movieElem = getDocumentElement(domNodes);
getNodes = movieElem.getElementsByTagName('movieSync'); % one node per video segment
len = getLength(getNodes);
if  len == 0, error('No segements found for this participant, ensure video files are present'); end
vidStruct = struct('fileName',{},'eegBeginSec',{}, 'eegEndSec', {}, 'videoBeginSec', {}, 'videoEndSec', {});
for k = 0: len - 1   % xml NodeList is 0-indexed
    seg = getNodes.item(k);
    vidStruct(k+1).fileName = getXMLChildText(seg,'fileName');
    vidStruct(k+1).eegBeginSec = str2double(getXMLChildText(seg,'sampleBeginTime'))/1e6;
    vidStruct(k+1).eegEndSec = str2double(getXMLChildText(seg,'sampleEndTime'))/1e6;
    vidStruct(k+1).videoBeginSec = str2double(getXMLChildText(seg,'videoBeginTime'));
    vidStruct(k+1).videoEndSec = str2double(getXMLChildText(seg,'videoEndTime'));
end
end
% text of the first <tag> child under node
function tagout = getXMLChildText(node,tag)
    nodeOut = node.getElementsByTagName(tag);
    nodeItem = nodeOut.item(0);
    tagout = char(nodeItem.getFirstChild().getNodeValue());
end