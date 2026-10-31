"""Points on the MakeHuman base mesh that match the face landmarks the game
finds in a photo (game/scripts/player_face_fit.gd), so a face can be fitted
from a photo.

Each point is one vertex of the body mesh, found from the mesh's shape (the
middle line of the face, its outline seen from the front) or from MakeHuman's
own targets (the eye corners are the ends of the patch an eye's "move out"
target moves rigidly; the mouth corners and nose wings are where the
"wider" targets push furthest out). The landmark names and their
order must match PlayerFaceFit.POINTS.

MakeHuman coordinates: +x is the person's left, +y up, +z the way they face.
"""

import os

import numpy as np

import mhuman

POINTS = [
    "r_eye_outer", "r_eye_inner", "l_eye_inner", "l_eye_outer",
    "r_brow", "l_brow",
    "nose_tip", "r_nose_wing", "l_nose_wing",
    "r_mouth", "l_mouth", "upper_lip", "lower_lip",
    "chin", "r_jaw", "l_jaw", "r_cheek", "l_cheek", "r_jaw_low", "l_jaw_low",
]


def find(human, eyebrows):
    """Landmark name -> body vertex index, on the human's current coords.
    `eyebrows` is the eyebrows' .mhclo."""
    p = human.coords
    faces = human.body_faces()
    used = np.unique([v for f in faces for v, _ in f])
    out = {}

    def moved(target):
        idx, d = mhuman.read_target(os.path.join(human.data, "targets", target + ".target.gz"))
        full = np.zeros_like(p)
        full[idx] = d
        return full

    body = np.zeros(len(p), bool)
    body[used] = True
    for side in ("l", "r"):
        m = np.linalg.norm(moved(f"eyes/{side}-eye-trans-out"), axis=1)
        eye = np.nonzero(body & (m >= 0.98 * m[body].max()))[0]
        xs = np.abs(p[eye, 0])
        out[f"{side}_eye_outer"] = eye[int(np.argmax(xs))]
        out[f"{side}_eye_inner"] = eye[int(np.argmin(xs))]
    eye_y = p[[out[k] for k in ("l_eye_outer", "r_eye_outer", "l_eye_inner", "r_eye_inner")], 1].mean()
    eye_z = p[[out["l_eye_outer"], out["r_eye_outer"]], 2].mean()
    eye_span = p[out["l_eye_outer"], 0] - p[out["r_eye_outer"], 0]

    def widest(target):
        dx = moved(target)[:, 0] * np.sign(p[:, 0])
        dx[~body] = -1.0
        left = np.where(p[:, 0] > 0, dx, -1.0)
        right = np.where(p[:, 0] < 0, dx, -1.0)
        return int(np.argmax(left)), int(np.argmax(right))

    out["l_mouth"], out["r_mouth"] = widest("mouth/mouth-scale-horiz-incr")
    out["l_nose_wing"], out["r_nose_wing"] = widest("nose/nose-scale-horiz-incr")
    mouth_y = p[[out["l_mouth"], out["r_mouth"]], 1].mean()

    # The middle line of the face, in front of the eyes' corners.
    mid = used[(np.abs(p[used, 0]) < 1e-3) & (p[used, 2] > eye_z - 0.3 * eye_span)]
    above = mid[(p[mid, 1] < eye_y) & (p[mid, 1] > mouth_y)]
    out["nose_tip"] = above[int(np.argmax(p[above, 2]))]
    nose_y = p[out["nose_tip"], 1]
    lips = mid[np.abs(p[mid, 1] - mouth_y) < 0.25 * eye_span]
    upper = lips[p[lips, 1] > mouth_y]
    lower = lips[p[lips, 1] < mouth_y]
    # The lips' outer edges: where the middle line turns most sharply back
    # in towards the face above and below the mouth. Approximated as the
    # lips' furthest-forward points.
    out["upper_lip"] = upper[int(np.argmax(p[upper, 2] - 0.3 * (p[upper, 1] - mouth_y)))]
    out["lower_lip"] = lower[int(np.argmax(p[lower, 2] + 0.3 * (p[lower, 1] - mouth_y)))]
    # The chin's lowest point seen from the front: the lowest point of the
    # middle line not far behind the front of the chin.
    centre = used[np.abs(p[used, 0]) < 1e-3]
    chin = centre[(p[centre, 1] < p[out["lower_lip"], 1] - 0.1 * eye_span) & (p[centre, 1] > mouth_y - 0.9 * eye_span)]
    chin_z = p[chin, 2].max()
    below = chin[p[chin, 2] > chin_z - 0.25 * eye_span]
    out["chin"] = below[int(np.argmin(p[below, 1]))]

    front = used[p[used, 2] > eye_z - 0.6 * eye_span]
    # The face's outline seen from the front: widest point at a height.
    def outline(y, tol):
        row = front[np.abs(p[front, 1] - y) < tol]
        return row[int(np.argmax(p[row, 0]))], row[int(np.argmin(p[row, 0]))]

    out["l_jaw"], out["r_jaw"] = outline(mouth_y, 0.04 * eye_span)
    chin_y = p[out["chin"], 1]
    out["l_jaw_low"], out["r_jaw_low"] = outline(mouth_y - 0.58 * (mouth_y - chin_y), 0.04 * eye_span)
    out["l_cheek"], out["r_cheek"] = outline((eye_y + nose_y) / 2, 0.04 * eye_span)

    # Brows: the skin under the middle of each eyebrow.
    brows = mhuman.Proxy(eyebrows).fit(p)
    for side in ("l", "r"):
        cx = p[[out[f"{side}_eye_outer"], out[f"{side}_eye_inner"]], 0].mean()
        near = brows[np.abs(brows[:, 0] - cx) < 0.08 * eye_span]
        spot = near.mean(axis=0)
        out[f"{side}_brow"] = front[int(np.argmin(np.linalg.norm(p[front] - spot, axis=1)))]
    return {k: int(out[k]) for k in POINTS}
